test -n "$_makeplist_" && return 0
readonly _makeplist_=1

. ${bsda_dir:-.}/bsda_container.sh
. ${bsda_dir:-.}/pkg_info.sh
. ${bsda_dir:-.}/bsda_opts.sh
. ${bsda_dir:-.}/bsda_util.sh

#
# Each instance represents an option in a linked list.
#
# Along with the name of the option, the names of the options in
# `${opt}_IMPLIES` and `${opt}_PREVENTS` are stored, both of which are
# taken into consideration by the getPair() method.
#
# The reference to the Options instance is used to resolve implied
# options.
#
bsda:obj:createClass makeplist:Option \
	a:public:Next=makeplist:Option \
	r:private:options  "The Options instance" \
	r:public:group     "The group this option is a member of" \
	r:public:name      "Name of this option" \
	r:public:implies   "Implied options" \
	r:public:prevents  "Conflicting options" \
	i:private:init     "Setup basic settings" \
	x:public:getPair   "Returns the WITH and WITHOUT pair for this option"

#
# Initialise all members.
#
# @param 1
#	The options manager instance
# @param 2
#	The group the option is a member of
# @param 3
#	The option to provide a configuration for
# @param 4
#	The implied options
# @param 5
#	The prevented options
#
makeplist:Option.init() {
	setvar ${this}options "$1"
	setvar ${this}group "$2"
	setvar ${this}name "$3"
	setvar ${this}implies "$4"
	setvar ${this}prevents "$5"
}

#
# Recursively retrieves the option and its implications.
#
# It creates two lists, a `WITH` and `WITHOUT` list of options. The
# `WITH` list contains the option itself and recursively its implied
# options. The `WITHOUT` list contains the prevented options and
# the options prevented by the recursively implied options.
#
# If the option is part of an `OPTIONS_SINGLE` group, the siblings
# are added to the `WITHOUT` list.
#
# @param &1
#	The variable to return the `WITH` selection to
# @param &2
#	The variable to return the `WITHOUT` selection to
# @param 3,4
#	Options already in `WITH` and `WITHOUT` respectively
# @retval 0
#	Returning options succeeded or the option was already in the
#	list provided by $3, in the latter case nothing is written
#	to the return variables
# @retval 1
#	This configuration is conflicting, i.e. an option is implied
#	and prevented at the same time. The return variables are
#	not written
#
makeplist:Option.getPair() {
	local IFS with without name
	with="$3"
	without="$4"
	$this.getName name
	# Already listed
	bsda:util:in "$name" $with && return 0
	# Already listed in prevents?
	bsda:util:in "$name" $without && return 1
	# Add self
	with="${with:+$with }$name"

	# Lists of options are space separated
	IFS=' '

	# Add prevents to without
	local prevents prevent
	$this.getPrevents prevents
	for prevent in $prevents; do
		bsda:util:in "$prevent" $without && continue
		bsda:util:in "$prevent" $with && return 1
		without="${without:+$without }$prevent"
	done

	# Add siblings in single groups to without
	local group groupMap options map members member
	$this.getOptions options
	$this.getGroup group
	if [ -z "${group##OPTIONS_SINGLE_*}" ]; then
		$options.GroupMap map
		$map.[ "$group" ] members
		for member in $members; do
			test "$member" = "$name" && continue
			bsda:util:in "$member" $without && continue
			bsda:util:in "$member" $with && return 1
			without="${without:+$without }$member"
		done
	fi

	# Recursively add implies
	local implies options map option
	$this.getImplies implies
	$options.OptionMap map
	for name in $implies; do
		$map.[ "$name" ] option
		$option.getPair with without "$with" "$without" || return 1
	done
	$caller.setvar "$1" "$with"
	$caller.setvar "$2" "$without"
	return 0
}

#
# Represents all options of the port in the current directory.
#
# Every option is stored in a linked list, starting with the First
# member. The list is simply for storage and for iterating through
# it to generate build configurations. The OptionMap maps option
# names to objects in the list.
#
# There are two kinds of relationships between options, `${opt}_IMPLIES`
# and `${opt}_PREVENTS` are stored with each option, common membership
# in a group is stored in the GroupMap.
#
# The names of groups are fully qualified, e.g. `OPTIONS_DEFINE`,
# `OPTIONS_GROUP_FOO`, `OPTIONS_SINGLE_BAR`. Thus the name of a group
# also implies the rules governing it. The only rule really mattering
# here is that `OPTIONS_SINGLE_*` and `OPTIONS_MULTI_*` groups always
# have to be represented in build configurations.
#
bsda:obj:createClass makeplist:Options \
	a:private:First=makeplist:Option \
	a:public:GroupMap=bsda:container:Map \
	a:public:OptionMap=bsda:container:Map \
	r:private:select   "The currently selected option" \
	r:private:hasMulti "Set if SINGLE or MULTI groups exist" \
	i:private:init     "Setup all groups of options" \
	x:public:next      "Select the next option for testing" \
	x:public:getPair   "Returns the WITH and WITHOUT pair for the option" \
	x:public:getName   "Returns the name of the option to test"

#
# Use `options.mk` to retrieve all options and set everything up.
#
makeplist:Options.init() {
	local groupMap optionMap groups options
	bsda:container:Map ${this}GroupMap
	bsda:container:Map ${this}OptionMap
	setvar ${this}select
	setvar ${this}hasMulti
	$this.GroupMap groupMap
	$this.OptionMap optionMap

	eval "$(/usr/bin/make -f${bsda_dir:-.}/options.mk \
	                      -V"groups='\${BSDA_GROUPS:ts\\n}'" \
	                      -V"options='\${BSDA_OPTIONS:ts\\n}'")" || return

	# Create groups
	local line group members hasMulti
	hasMulti=
	for line in $groups; do
		bsda:util:map "$line" \| group members
		bsda:util:split members ,
		# Create group
		$groupMap.[ "$group" ]= "$members"
		# Detect single/multi groups
		case "$group" in
		OPTIONS_SINGLE_*|OPTIONS_MULTI_*)
			hasMulti=1
		;;
		esac
	done

	# Create options
	local line group name implies prevents option last
	last=
	for line in $options; do
		bsda:util:map "$line" \| group name implies prevents
		bsda:util:split implies ,
		bsda:util:split prevents ,
		# Create option
		makeplist:Option option $this "$group" "$name" "$implies" "$prevents"
		# Map name → option
		$optionMap.[ "$name" ]= $option
		# Update list of options
		if [ -z "$last" ]; then
			setvar ${this}First $option
		else
			setvar ${last}Next $option
		fi
		last=$option
	done

	# If there are mandatory groups, skip the build attempt without flags.
	if [ -n "$hasMulti" ]; then
		setvar ${this}hasMulti 1
		$this.First ${this}select
	fi
}

#
# Select the next configuration of options.
#
# @retval 0
#	The next option has been selected
# @retval 1
#	Select beyond the last configuration, starting over
#
makeplist:Options.next() {
	local select multi
	$this.getSelect select
	if ! makeplist:Option.isInstance "$select"; then
		$this.First select
	else
		$select.Next select
	fi
	setvar ${this}select "$select"
	test -n "$select" && return 0

	# Moved beyond the last option, if OPTIONS_SINGLE or OPTIONS_MULTI
	# groups are present the first option should be selected instead
	# of trying to build without flags the next time.
	$this.getHasMulti multi
	if [ -n "$multi" ]; then
		$this.First ${this}select
	fi
	return 1
}

#
# Lambda to retrieve `OPTIONS_SINGLE` and `OPTIONS_MULTI` groups.
#
# @param multis
#	The group members are added to this variable, each group
#	is followed by the contents of IFS
# @param IFS
#	Should be set to a newline
#
makeplist:Options.getPair_multis() {
	case "$1" in
	OPTIONS_SINGLE_*|OPTIONS_MULTI_*)
		multis="$multis$2$IFS"
	;;
	esac
}

#
# Lambda to collect all options that have not yet been selected.
#
# @param with
#	The list of options to build with
# @param without
#	All unused options are added to this list
#
makeplist:Options.getPair_without() {
	local IFS member
	IFS=' '
	for member in $2; do
		if ! bsda:util:in "$member" $with $without; then
			without="${without:+$without }$member"
		fi
	done
}

#
# Tries to retrieve a valid set of options for the currently selected
# configuration.
#
# The selection contains:
#
# - The selected option and its implications
# - One of each OPTIONS_SINGLE group and their implications
# - One of each OPTIONS_MULTI group and their implications
#
# @param &1
#	The variable to return the `WITH` selection to
# @param &2
#	The variable to return the `WITHOUT` selection to
# @retval 0
#	Creating a configuration succeeded
# @retval 1
#	A configuration without conflicts was not found, the return
#	variables have not been written
#
makeplist:Options.getPair() {
	local select with without
	# Get the selected option
	$this.getSelect select
	if [ -n "$select" ]; then
		$select.getPair with without || return
	else
		with=
		without=
	fi

	# Get a representative of each SINGLE/MULTI group
	local IFS groupMap optionMap multis members member
	local option implies prevents
	IFS='
'
	$this.GroupMap groupMap
	$this.OptionMap optionMap
	multis=
	$groupMap.foreach $class.getPair_multis
	for members in $multis; do
		IFS=' '
		# Skip already represented groups
		for member in $members; do
			bsda:util:in "$member" $with && continue 2
		done
		# Try to find an option without implications or prevents
		for member in $members; do
			$optionMap.[ "$member" ] option
			$option.getImplies implies
			$option.getPrevents prevents
			if [ -z "$implies$prevents" ] && \
			   $option.getPair with without "$with" "$without"; then
				# Move on to the next group
				continue 2
			fi
		done
		# Try to find an option without prevents
		for member in $members; do
			$optionMap.[ "$member" ] option
			$option.getPrevents prevents
			if [ -z "$prevents" ] && \
			   $option.getPair with without "$with" "$without"; then
				# Move on to the next group
				continue 2
			fi
		done
		# Just try to find an option that works
		for member in $members; do
			$optionMap.[ "$member" ] option
			if $option.getPair with without "$with" "$without"; then
				# Move on to the next group
				continue 2
			fi
		done
		# Couldn't find an option that works!
		return 1
	done

	# Just add all unused options to without
	$groupMap.foreach $class.getPair_without

	# Return selection
	$caller.setvar "$1" "$with"
	$caller.setvar "$2" "$without"
	return 0
}

#
# Returns the name of the currently selected option.
#
# @param &1
#	The variable to return the name to
#
makeplist:Options.getName() {
	local select name
	name=
	$this.getSelect select
	test -n "$select" && $select.getName name
	$caller.setvar "$1" "$name"
}

#
# This deletes the given file when deleted.
#
# This is a simple RAII wrapper.
#
bsda:obj:createClass makeplist:File \
	r:private:filename "Name of the file to remove" \
	i:private:init     "The constructor" \
	c:private:clean    "The destructor, removes the file"

#
# Store the filename.
#
# @param 1
#	The filename
#
makeplist:File.init() {
	test -n "$1" || return
	setvar ${this}filename "$1"
}

#
# Remove the file.
#
makeplist:File.clean() {
	local filename
	$this.getFilename filename
	/bin/rm -f "$filename"
}

#
# A container and a linked list class for plists of a single build/stage.
#
bsda:obj:createClass makeplist:Plist \
	a:public:Next=makeplist:Plist \
	r:public:retval  "The return status of the build/stage" \
	r:public:logfile "The name of the logfile to the build/stage" \
	r:public:with    "The options the build/stage was done with" \
	r:public:without "The options the build/stage was done without" \
	r:public:files   "The files found in the staging area" \
	r:public:session "The Session instance (for printing)" \
	c:private:report "The destructor reports failed build/stage attempts"

#
# Prints a notification if the build/stage returned a non-zero exit
# status.
#
makeplist:Plist.report() {
	local retval session with without logfile
	$this.getRetval retval
	# Skip successful builds
	test 0 -eq "$retval" && return 0
	$this.getSession session
	$this.getWith with
	$this.getWithout without
	$this.getLogfile logfile
	$session.error "Building/staging returned $retval: $with"
	echo "A build log is available: $logfile"
}

#
# Manage the linked list of per build plists.
#
bsda:obj:createClass makeplist:PlistManager \
	a:private:First=makeplist:Plist \
	r:private:tail          "The last entry in the list" \
	r:private:session       "The Session instance (for printing)" \
	r:private:mtree_file    "The value of MTREE_FILE" \
	r:private:stagedir      "The value of STAGEDIR" \
	r:private:prefix        "The value of PREFIX" \
	r:private:optionsSorted "A sorted list of all options" \
	x:private:plistFilter   "Returns a list of grep -v filters" \
	x:private:plistSubSed   "Retruns a list of sed instructions" \
	i:private:init          "The constructor populates members" \
	x:public:create         "Create a plist entry" \
	x:public:plist          "Produce the plist"

#
# Construct the manager, pull all the required variables from make.
#
makeplist:PlistManager.init() {
	local prefix
	setvar ${this}session "$1"
	setvar ${this}mtree_file "$(/usr/bin/make -VMTREE_FILE)" || return
	setvar ${this}stagedir "$(/usr/bin/make -VSTAGEDIR)" || return
	setvar ${this}prefix "$(/usr/bin/make -VPREFIX)" || return
	setvar ${this}optionsSorted "$(
		/usr/bin/make -V'SELECTED_OPTIONS:ts\n' \
		              -V'DESELECTED_OPTIONS:ts\n' \
		| /usr/bin/sort -n)" || return
}

#
# Returns filtering rules to apply using `grep -v`.
#
# The filtering rules are based on the following make variables:
#
# | Variable          | Description                                      |
# |-------------------|--------------------------------------------------|
# | `DESKTOP_ENTRIES` | Macro for creating/installing desktop icons      |
# | `USE_RC_SUBR`     | Macro for creating/installing rc(8) scripts      |
# | `PLIST_FILES`     | A list of files automatically added to the plist |
# | `PORTDOCS`        | A list of files / glob patterns in DOCSDIR       |
# | `PORTEXAMPLES`    | A list of files / glob patterns in EXAMPLESDIR   |
# | `PORTDATA`        | A list of files / glob patterns in DATADIR       |
#
# @param &1
#	The variable to return the filter list to
# @param 2,3
#	The options to build WITH and WITHOUT
# @retval 0
#	Creating the filter list succeeded
# @retval *
#	Creating the filter list failed
#
makeplist:PlistManager.plistFilter() {
	local filter
	filter="$( (
		/usr/bin/make WITH="$2" WITHOUT="$3" \
		              -V'${DESKTOP_ENTRIES:S,^/,,:C,[/ ],_,g:C,[^_[:alnum:]],,g:S,$$,.desktop$$,:S,^,${DESKTOPDIR:S,^${PREFIX}/,^,}/,:ts\n}' \
		| /usr/bin/awk 'NR % 6 == 4' || return
		/usr/bin/make WITH="$2" WITHOUT="$3" \
		              -V'${USE_RC_SUBR:S,^,^etc/rc.d/,:S,$$,$$,:ts\n}' \
		              -V'${PLIST_FILES:S,^${PREFIX}/,,:S,^,^,:S,$$,$$,:ts\n}' \
		| /usr/bin/vis -ce '.[]*?' || return
		/usr/bin/make -WITH="$2" WITHOUT="$3" \
		              -V'${PORTDOCS:S,^,^${DOCSDIR_REL}/,:ts\n}' \
		              -V'${PORTEXAMPLES:S,^,^${EXAMPLESDIR_REL}/,:ts\n}' \
		              -V'${PORTDATA:S,^,^${DATADIR_REL}/,:ts\n}' \
		| /usr/bin/sed 's/\*/.*/g;s/\?/./g' || return
	) | /usr/bin/grep .)" || return
	$caller.setvar "$1" "$filter"
}

#
# Generates sed instructions from PLIST_SUB.
#
# @param &1
#	The variable to return the sub list to.
# @retval 0
#	Creating the sub list succeeded
# @retval *
#	Creating the sub list failed
#
makeplist:PlistManager.plistSubSed() {
	local IFS sublist exprs sub prefix W
	IFS='
'
	sublist="$(/usr/bin/make -VPLIST_SUB:ts\\n)" || return
	# Sort by replacement size so the biggest match wins
	sublist="$(
		for sub in $sublist; do
			tail="${sub#*=}"
			tail="${tail#\"}";tail="${tail%\"}"
			case "$tail" in
			''|@*)
				continue
			;;
			esac
			tail="$(echo -n "$tail" | /usr/bin/vis -ce '.[]*?!+{}')"
			echo "${#tail} ${sub%%=*}=$tail"
		done | /usr/bin/sort -rn | /usr/bin/sed 's/^[0-9]* //'
	)"
	# Create sed expressions
	W='[^[:alnum:]]' # \W does not work, \b and \B neither
	exprs='/\.sample$/s!^!@sample !;'
	$this.getPrefix prefix
	for sub in $sublist; do case "$sub" in
	LIB32DIR=*|PREFIX=*|*=$prefix)
	;;
	*DIR=*)
		exprs="${exprs}s!(^|$W)${sub#*=}/!\1%%${sub%%=*}%%/!;"
	;;
	*)
		exprs="${exprs}s!(^|$W)${sub#*=}(\$|$W)!\1%%${sub%%=*}%%\2!;"
	;;
	esac; done
	exprs="${exprs}s!^%%(DOCS|EXAMPLES)DIR%%!%%PORT\1%%%%\1DIR%%!;"
	$caller.setvar "$1" "$exprs"
}

#
# Create a plist entry for the last build/stage.
#
# @param 1
#	The return value of the build/stage
# @param 2
#	The log file for the build/stage
# @param 3,4
#	The options the build/stage was performed WITH and WITHOUT
#
makeplist:PlistManager.create() {
	# Update linked list
	local plist tail
	$this.getTail tail
	makeplist:Plist plist "$@"
	if makeplist:Plist.isInstance "$tail"; then
		setvar ${tail}Next "$plist"
	else
		setvar ${this}First "$plist"
	fi
	setvar ${this}tail "$plist"

	# Populate new list entry
	setvar ${plist}retval "$1"
	setvar ${plist}logfile "$2"
	setvar ${plist}with "$3"
	setvar ${plist}without "$4"
	$this.getSession ${plist}session
	# Generate list of files
	local stagedir prefix mtree_file plistFilter
	$this.getStagedir stagedir
	$this.getPrefix prefix
	$this.getMtree_file mtree_file
	$this.plistFilter plistFilter "$3" "$4"
	setvar ${plist}files "$( (
		/usr/bin/find "$stagedir" \( -type f -o -type l \) \
		              -not -path "$stagedir$prefix/*" 2> /dev/null \
		| /usr/bin/sort -n \
		| /usr/bin/sed "s!^$stagedir!!"
		/usr/sbin/mtree -cp "$stagedir$prefix/" 2> /dev/null \
		| /usr/sbin/mtree -f /dev/stdin -f "$mtree_file" \
		| /usr/bin/sort -n \
		| /usr/bin/awk '/ (file|link) [^\/]*/{sub(/ (file|link) [^\/]*/, "");print}'
	) | /usr/bin/grep -v "$plistFilter" )"
}

#
# Takes a stream of per build packaging lists and outputs the complete
# plist.
#
# Every plist should be preceded by a line starting with `OPTIONS: `
# followed by a list of options the build/stage was done with.
#
# Files are output in the order of input and grouped by options in
# the given order.
#
# @param @
#	All options in the order they should be output in
#
makeplist:PlistManager.plist_filter() { /usr/bin/awk '
	# Get the order of options
	BEGIN {
		OPTION_STR["DOCS"] =     "%%PORTDOCS%%"
		OPTION_STR["EXAMPLES"] = "%%PORTEXAMPLES%%"
		for (i = 1; i < ARGC; ++i) {
			OPTIONS_ORDERD[i] = ARGV[i]
			CNT_OPT_FILES[ARGV[i]] = 0
			if (!(ARGV[i] in OPTION_STR)) {
				OPTION_STR[ARGV[i]] = "%%" ARGV[i] "%%"
			}
			if (!("NO_" ARGV[i] in OPTION_STR)) {
				OPTION_STR["NO_" ARGV[i]] = "%%NO_" ARGV[i] "%%"
			}
			delete ARGV[i]
		}
		CNT_FILES = 0
	}
	# Get the options the following files were staged with
	/^OPTIONS:/ {
		delete aoptions
		sub(/^OPTIONS: */, "")
		cnt_aoptions = split($0, aoptions)
		for (i = 1; i <= cnt_aoptions; ++i) {
			++OPTIONS[aoptions[i]]
		}
		++CONFIGS
		next
	}
	# Collect files
	{
		# Record order of file
		if (!($0 in FILES)) {
			FILES_ORDERED[++CNT_FILES] = $0
		}
		# Count occurence of file
		++FILES[$0]
		# The same book keepin per option
		for (i = 1; i <= cnt_aoptions; ++i) {
			option = aoptions[i]
			# Record order of file for option
			if (!OPT_FILES[option, $0]) {
				OPT_FILES_ORDERED[option, ++CNT_OPT_FILES[option]] = $0
			}
			# Count occurence of file by option
			++OPT_FILES[option, $0]
		}
	}
	# Print files
	END {
		# Print files common to all configurations
		for (i = 1; i <= CNT_FILES; ++i) {
			file = FILES_ORDERED[i]
			if (FILES[file] == CONFIGS) {
				print file
				delete FILES[file]
			}
		}
		# Print option specific files
		for (i = 1; OPTIONS_ORDERD[i]; ++i) {
			option = OPTIONS_ORDERD[i]
			for (p = 1; p <= CNT_OPT_FILES[option]; ++p) {
				file = OPT_FILES_ORDERED[option, p]
				# Skip files that have already been printed
				if (!(file in FILES)) { continue }
				# Print file if it only occurs for the current
				# option
				if (OPT_FILES[option, file] == OPTIONS[option] &&
				    OPT_FILES[option, file] == FILES[file]) {
					print OPTION_STR[option] file
					delete FILES[file]
				}
			}
			for (p = 1; p <= CNT_FILES; ++p) {
				file = FILES_ORDERED[p]
				if (!(file in FILES)) { continue }
				# Print file if it occurs everywhere but with
				# this option
				if (!OPT_FILES[option, file] &&
				    FILES[file] + OPTIONS[option] == CONFIGS) {
					print OPTION_STR["NO_" option] file
					delete FILES[file]
				}
			}
		}
		# Print all files that have not been printed
		for (i = 1; i <= CNT_FILES; ++i) {
			file = FILES_ORDERED[i]
			if (!(file in FILES)) { continue }
			print "@fail " file " could not be mapped to an option!"
			msg = "@fail Candidates:"
			for (p = 1; OPTIONS_ORDERD[p]; ++p) {
				if (OPT_FILES[OPTIONS_ORDERD[p], file]) {
					msg = msg " " OPTIONS_ORDERD[p]
				}
			}
			print msg
		}
	}
' "$@";}

#
# Generate the packaging list.
#
# @param &1
#	The variable to return the plist to
#
makeplist:PlistManager.plist() {
	$caller.setvar "$1" "$(
		$this.getOptionsSorted options
		$this.plistSubSed subsed
		$this.First plist
		while [ -n "$plist" ]; do
			$plist.getRetval retval
			# Skip failed builds
			if [ 0 -ne "$retval" ]; then
				$plist.Next plist
				continue
			fi
			$plist.getWith with
			echo OPTIONS: $with
			$plist.getFiles
			$plist.Next plist
		done | $class.plist_filter $options | /usr/bin/sed -E "$subsed"
	)"
}

#
# Creates a temporary directory.
#
# The temporary directory is automatically deleted along with the
# class instance if it is empty.
#
bsda:obj:createClass makeplist:TmpDir \
	r:private:dirname "The name of the directory" \
	i:private:init    "Create the temporary directory" \
	c:private:clean   "Remove the temporary directory"

#
# Creates the temporary directory and returns its name.
#
# @param &1
#	The variable to return the dirname to
# @param 2
#	The optional mktemp template
#
makeplist:TmpDir.init() {
	setvar ${this}dirname "$(/usr/bin/mktemp -d ${2:+-t "$2"})" || return
	local dirname
	$this.getDirname dirname
	$caller.setvar "$1" "$dirname"
}

#
# Silently try to remove the temporary directory.
#
makeplist:TmpDir.clean() {
	local dirname
	$this.getDirname dirname
	/bin/rmdir "$dirname" 2> /dev/null || :
}

#
# Manage build/stage attempts.
#
bsda:obj:createClass makeplist:Make \
	a:private:Logdir=makeplist:TmpDir \
	a:private:Plists=makeplist:PlistManager \
	r:private:session      "The Session instance (for printing)" \
	r:private:logdir       "The name of the logging directory" \
	r:private:no_build     "The value of make -VNO_BUILD" \
	r:private:plistOldFile "The value of make -VPLIST" \
	r:private:plistNewFile "The name of the new plist file" \
	i:private:init         "Construct an instance" \
	x:public:run           "Perform a build/stage cycle" \
	x:public:plist         "Generate a plist"

#
# Initialise all attributes and aggregations
#
# @param 1
#	The Session instance, used for printing
# @param 2
#	The optional name of the new plist file
# @retval 0
#	Creating a Make instance succeeded
# @retval *
#	In case of an error
#
makeplist:Make.init() {
	local origin wrkdir file
	setvar ${this}session "$1"
	setvar ${this}plistNewFile "$2"
	origin="$(/usr/bin/make -VPKGORIGIN)" || return
	if [ -z "$origin" ]; then
		$1.error "Port origin could not be detected"
		return 1
	fi
	wrkdir="$(/usr/bin/make -VWRKDIR)" || return
	if ! /bin/mkdir -p "$wrkdir" 2> /dev/null; then
		$1.error "The WRKDIR could not be created: $wrkdir"
		return 1
	fi
	if ! [ -w "$wrkdir" ]; then
		$1.error "The WRKDIR is not writable: $wrkdir"
		return 1
	fi
	$1.msg "Initialising make for $origin"
	origin="$(echo "$origin" | /usr/bin/tr / .)"
	file="$(/usr/bin/make -VPLIST)" || return
	setvar ${this}plistOldFile "$file"
	test -z "$2" && setvar ${this}plistNewFile "$file.${0##*/}"
	$this.getPlistNewFile file
	if ! /usr/bin/touch "$file" 2> /dev/null; then
		$1.error "The target plist-file is not writable: $file"
		return 1
	fi
	makeplist:TmpDir ${this}Logdir ${this}logdir "${0##*/}.$origin" \
	|| return
	makeplist:PlistManager ${this}Plists "$1" || return
	setvar ${this}no_build "$(/usr/bin/make -VNO_BUILD)" || return
}

#
# Execute `make` with the given options.
#
# Executes `make` keeps logs of failed builds and collects staged
# files for later plist creation.
#
# @param 1,2
#	The options to build with and without
#
makeplist:Make.run() {
	local retval plists no_build stagedir prefix mtree_file
	local logdir logfilename opts logfile session oflags
	$this.getSession session
	$session.OptsFlags oflags
	$this.getLogdir logdir
	bsda:util:join opts - $1
	logfilename="$logdir/stage${opts:+-$opts}.log"
	makeplist:File logfile "$logfilename"
	$caller.delete $logfile
	$this.Plists plists
	$this.getNo_build no_build
	# Perform build in subprocess to protect outputs and environment
	(
		# Select staging target
		if [ -n "$no_build" ]; then
			targets="restage"
		else
			targets="clean stage"
		fi
		# Disable license features unless specifically requested
		if $oflags.check LICENSES -eq 0; then
			export DISABLE_LICENSES=1
		fi
		# Log configuration
		echo "WITH=$1" > "$logfilename"
		echo "WITHOUT=$2" >> "$logfilename"
		/usr/bin/printenv >> "$logfilename"
		# Execute make in quiet mode
		if $oflags.check QUIET -ne 0; then
			# Cannot be interactive in quiet mode
			export BATCH=1
			# Close outputs
			exec 2>&- >&-
			# The interrupt.mk trick does not work after
			# closing the outputs, but because this is
			# a non-interactive session, backgrounding
			# and waiting for it works fine.
			exec /usr/bin/script -aq "$logfilename" \
			     /usr/bin/make $targets WITH="$1" WITHOUT="$2" &
			wait $!
			return $?
		fi
		# Call make inside script:
		# - Call make inside script for logging
		# - Call port Makefile through interrupt.mk to send
		#   a signal back, if make is interrupted
		exec /usr/bin/script -aq "$logfilename" \
		     /usr/bin/make -f"${bsda_dir:-.}/interrupt.mk" BSDA_PID=$$ \
		                   $targets WITH="$1" WITHOUT="$2"
	)
	retval=$?

	# Collect return status and files
	$plists.create "$retval" "$logfilename.gz" "$@"

	# Keep logs of failed builds
	if [ 0 -ne $retval ]; then
		$session.error "Staging failed with exit status: $retval"
		/usr/bin/gzip -9 "$logfilename"
	fi
}

#
# A filter transplanting @ keywords from the old plist to the next.
#
# Some of the keywords effect the files listed after them (e.g. @owner),
# so the script tries to place them in the same context in the new
# plist.
#
# Note that an automatically added @sample gets stripped here if
# the file is present in the old plist without it.
#
# @param 1
#	The new plist file name
# @param 2
#	The old plist file name
#
makeplist:Make.plist_keywords() { /usr/bin/awk '
	BEGIN {
		# List of auto-prefixes
		AUTO["@sample "]
	}

	# Index the new plist file
	NR == FNR {
		PLIST[NR] = $0
		PLIST_IND[$0] = NR
		PLIST_CNT = NR
		next
	}

	# Index the old plist file
	{
		OLD_PLIST[NR - PLIST_CNT] = $0
		OLD_PLIST_CNT = NR - PLIST_CNT
		# Strip auto-prefixes from the new plist if the file
		# is listed but does not have the prefix.
		for (auto in AUTO) {
			if (auto $0 in PLIST_IND) {
				PLIST[PLIST_IND[auto $0]] = $0
			}
		}
	}

	# Print plist
	END {
		PLIST_PRINT = 1
		# Find keyword in old plist
		for (NR = 1; NR <= OLD_PLIST_CNT; ++NR) {
			# Accumulate files that come before the next
			# keyword.
			PREVIOUS[OLD_PLIST[NR]]

			# Check for keyword
			if (OLD_PLIST[NR] ~ /(^|%%)@[[:alnum:]]+ /) {
				# Skip if already in new plist
				if (OLD_PLIST[NR] in PLIST_IND) {
					continue
				}
				# Read the new plist file from the
				# back until a line from the PREVIOUS
				# list is encountered.
				for (i = PLIST_CNT; i >= PLIST_PRINT; --i) {
					if (PLIST[i] in PREVIOUS) {
						break
					}
				}
				# Print everything before and including
				# the match.
				for (; PLIST_PRINT <= i; ++PLIST_PRINT) {
					print PLIST[PLIST_PRINT]
				}
				# Print the current (keyword) line
				print OLD_PLIST[NR]
			}
		}

		# Print remaining plist
		for (; PLIST_PRINT <= PLIST_CNT; ++PLIST_PRINT) {
			print PLIST[PLIST_PRINT]
		}
	}
' "$@";}

#
# Creates a new plist.
#
# Performs the following operations:
#
# - Assemble a new plist
# - Transplant @ keywords from the old pkg-plist
# - List lines removed, compared to old plist
# - List lines added, compared to old plist
# - Write new plist to file
#
makeplist:Make.plist() {
	local plists file plist origPlist change session
	$this.getSession session
	# Generate new plist
	$this.Plists plists
	$plists.plist plist
	if [ -z "$plist" ]; then
		$session.msg "The generated plist is empty"
		return 0
	fi
	# Get old plist
	$this.getPlistOldFile file
	if origPlist="$(/bin/cat "$file" 2> /dev/null)"; then
		# Transplant keywords
		plist="$(echo "$plist" | $class.plist_keywords - "$file")"
	fi
	# Print differences
	test -t 1 && /usr/bin/tput AF 1
	echo -n "$origPlist" | /usr/bin/grep -vFx "$plist" \
	                     | /usr/bin/sed 's/^/-/'
	test -t 1 && /usr/bin/tput AF 2
	echo -n "$plist" | /usr/bin/grep -vFx "$origPlist" \
	                 | /usr/bin/sed 's/^/+/'
	test -t 1 && /usr/bin/tput me

	# Print plist
	$this.getPlistNewFile file
	$session.msg "Printing plist to $file"
	echo "$plist" > "$file"

	# Ask for review
	if [ "$plist" != "$origPlist" ]; then
		$session.msg "The generated plist differs, please review!"
	fi
}

#
# The session class for makeplist.
#
bsda:obj:createClass makeplist:Session \
	a:public:OptsFlags=bsda:opts:Flags \
	a:private:Make=makeplist:Make \
	a:private:Options=makeplist:Options \
	r:private:outfile "The file to write the new plist to" \
	x:private:help    "Print usage information" \
	x:public:msg      "Print a message on stdout" \
	x:public:error    "Print an error message on stderr" \
	i:private:init    "Setup the session and run" \
	x:private:params  "Parse command line arguments" \
	x:private:run     "Perform plist creation"

#
# Prints the usage on stdout.
#
# @param 1
#	A bsda:opts:Options instance
#
makeplist:Session.help() {
	local usage
	$1.usage usage "\t%.2s, %-10s  %s\n"
	printf "usage: ${0##*/} [-h] [-o outfile] [port]\n%s" "$usage"
}

#
# Print a message on stdout.
#
# @param *
#	The message to print
#
makeplist:Session.msg() {
	if [ -t 1 ]; then
		printf '\033[38;5;3mmakeplist:\033[m %s\n' "$*"
	else
		printf 'makeplist: %s\n' "$*"
	fi
}

#
# Print an error message on stderr.
#
# @param *
#	The message to print
#
makeplist:Session.error() {
	if [ -t 1 ]; then
		printf '\033[38;5;3mmakeplist: \033[1;38;5;1mERROR:\033[m %s\n' "$*"
	else
		printf 'makeplist: ERROR: %s\n' "$*"
	fi 1>&2
}

#
# Setup the session and run.
#
# @param @
#	The command line arguments
#
makeplist:Session.init() {
	local outfile
	bsda:opts:Flags ${this}OptsFlags || return
	$this.params "$@" || return
	$this.getOutfile outfile
	makeplist:Make ${this}Make $this "$outfile" || return
	makeplist:Options ${this}Options || return
	$this.run || return
}

#
# Parses the command line arguments.
#
# @param @
#	The command line arguments
#
makeplist:Session.params() {
	local options flags option port

	bsda:opts:Options options \
	HELP     -h --help     'Print usage and exit' \
	LICENSES -l --licenses 'Enable ports(7) license auditing framework' \
	OUTFILE  -o --outfile  'Set the output file for the new plist' \
	QUIET    -q --quiet    'Suppress build output'
	$caller.delete $options

	$this.OptsFlags flags

	port=
	while [ $# -gt 0 ]; do
		$options.getopt option "$1"
		case "$option" in
		HELP)
			$this.help "$options"
			exit 0
		;;
		OUTFILE)
			if eval "[ -n \"\$${this}outfile\" ]"; then
				$this.error "More than one output file given: $2"
				return 1
			fi
			case "$2" in
			/*)
				setvar ${this}outfile "$2"
			;;
			*)
				setvar ${this}outfile "$PWD/$2"
			;;
			esac
			shift
		;;
		OPT_UNKNOWN)
			$this.error "Unknown parameter: \"$1\""
			return 1
		;;
		OPT_SPLIT)
			local arg
			arg="$1"
			shift
			set -- "${arg%${arg#-?}}" "-${arg#-?}" "$@"
			continue
		;;
		OPT_NOOPT)
			if [ -n "$port" ]; then
				$this.error "Too many arguments: ... $@"
				return 1
			fi
			port="$1"
		;;
		*)
			$flags.add "$option"
		;;
		esac
		shift
	done

	if $flags.check LICENSES -ne 0 && $flags.check QUIET -ne 0; then
		$this.error "The --licenses and --quiet flags are mutually exclusive."
		return 1
	fi

	case "$port" in
	''|/*)
	;;
	*/*)
		local portsdir
		portsdir="$(/usr/bin/make -f /usr/share/mk/bsd.port.mk -VPORTSDIR)"
		port="$portsdir/$port"
	;;
	*)
		local portsdir origin
		portsdir="$(/usr/bin/make -f /usr/share/mk/bsd.port.mk -VPORTSDIR)"
		origin="$(pkg:info:origins "$port")"
		if [ -z "$origin" ]; then
			$this.error "Cannot find port via \`pkg info\`: $port"
			return 1
		fi
		port="$portsdir/$origin"
	;;
	esac

	if [ -n "$port" ] && ! cd "$port"; then
		$this.error "Cannot change into port directory: $port"
		return 1
	fi
}

#
# Permute through the build options and generate a plist.
#
makeplist:Session.run() {
	local make options option with without count i
	$this.Make make
	$this.Options options

	# Go through all permutations to count them
	count=1
	while $options.next; do
		count=$((count + 1))
	done

	#
	# Run make for each permutation
	#

	# Get the initial state with no flags and all singles set
	# to the first option
	i=1
	if $options.getPair with without; then
		$this.msg "Building plist $i of $count${with:+: $with}"
		$make.run "$with" "$without"
	else
		$options.getName option
		$this.error "Could not find a valid configuration to test $option"
	fi

	# Try all options
	while $options.next; do
		i=$((i + 1))
		if $options.getPair with without; then
			$this.msg "Building plist $i of $count${with:+: $with}"
			$make.run "$with" "$without"
		else
			$options.getName option
			$this.error "Could not find a valid configuration to test $option"
		fi
	done

	# Generate the resulting plist
	$make.plist
}
