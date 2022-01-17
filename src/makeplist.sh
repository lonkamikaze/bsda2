test -n "$_makeplist_" && return 0
readonly _makeplist_=1

. ${bsda_dir:-.}/bsda_container.sh
. ${bsda_dir:-.}/pkg_info.sh
. ${bsda_dir:-.}/bsda_opts.sh
. ${bsda_dir:-.}/bsda_util.sh
. ${bsda_dir:-.}/bsda_bsdmake.sh

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
# If the option is part of an `OPTIONS_SINGLE` or `OPTIONS_RADIO`
# group, the siblings are added to the `WITHOUT` list.
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

	# Add siblings in single and radio groups to without
	local group groupMap options map members member
	$this.getOptions options
	$this.getGroup group
	case "$group" in
	OPTIONS_SINGLE_*|OPTIONS_RADIO_*)
		$options.GroupMap map
		$map.[ "$group" ] members
		for member in $members; do
			test "$member" = "$name" && continue
			bsda:util:in "$member" $without && continue
			bsda:util:in "$member" $with && return 1
			without="${without:+$without }$member"
		done
	;;
	esac

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

	eval "$(bsda:bsdmake -f${bsda_dir:-.}/options.mk \
	                     -V"groups='\${BSDA_GROUPS:ts\\n}'" \
	                     -V"options='\${BSDA_OPTIONS:ts\\n}'")" || return $?

	# Create groups
	local line group members hasMulti
	hasMulti=
	for line in $groups; do
		IFS=\| bsda:util:map "$line" group members
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
		IFS=\| bsda:util:map "$line" group name implies prevents
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
		$select.getPair with without || return $?
	else
		with=
		without=
	fi

	# Get a representative of each SINGLE/MULTI group
	local IFS groupMap optionMap multis members member
	local option implies prevents
	IFS=$'\n'
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
	test -n "$1" || return $?
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
# A container and a linked list class for the results of a single build/stage.
#
bsda:obj:createClass makeplist:Build \
	a:public:Next=makeplist:Build \
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
makeplist:Build.report() {
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
# Manage the linked list of builds.
#
bsda:obj:createClass makeplist:BuildManager \
	a:private:First=makeplist:Build \
	r:private:tail          "The last entry in the list" \
	r:private:session       "The Session instance (for printing)" \
	r:private:mtree_file    "The value of MTREE_FILE" \
	r:private:stagedir      "The value of STAGEDIR" \
	r:private:prefix        "The value of PREFIX" \
	r:private:optionsSorted "A sorted list of all options" \
	x:private:plistFilter   "Returns a list of grep -v filters" \
	x:private:plistSubSed   "Returns a list of sed instructions" \
	i:private:init          "The constructor populates members" \
	x:public:create         "Create a build entry" \
	x:public:plist          "Produce the plist"

#
# Construct the manager, pull all the required variables from make.
#
makeplist:BuildManager.init() {
	local prefix
	setvar ${this}session "$1"
	setvar ${this}mtree_file "$(bsda:bsdmake -VMTREE_FILE)" || return $?
	setvar ${this}stagedir "$(bsda:bsdmake -VSTAGEDIR)" || return $?
	setvar ${this}prefix "$(bsda:bsdmake -VPREFIX)" || return $?
	setvar ${this}optionsSorted "$(
		bsda:bsdmake -V'SELECTED_OPTIONS:ts\n' \
		             -V'DESELECTED_OPTIONS:ts\n' \
		| /usr/bin/sort -n)" || return $?
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
# This also adds a filter against including .orig files, unless the ORIG
# flag is set.
#
# @param &1
#	The variable to return the filter list to
# @param 2,3
#	The options to build WITH and WITHOUT
#
makeplist:BuildManager.plistFilter() {
	local filter session flags
	$this.getSession session
	# Create make based filter list
	filter="$( (
		$session.Vars vars
		($vars.get '' 'DESKTOP_ENTRIES:S,^/,,:C,[/ ],_,g:C,[^_[:alnum:]],,g:S,$$,.desktop$$,:S,^,${DESKTOPDIR:S,^${PREFIX}/,^,}/,:ts\n' \
		           -- WITH="$2" WITHOUT="$3" | /usr/bin/awk 'NR % 6 == 4'
		 $vars.get '' 'PLIST_FILES:S,^${PREFIX}/,,:S,^,^,:S,$$,$$,:ts\n' \
		              'USE_RC_SUBR:S,^,^etc/rc.d/,:S,$$,$$,:ts\n' \
		           -- WITH="$2" WITHOUT="$3") | /usr/bin/vis -ce '.[]*?'
		($vars.get '' 'PORTDOCS:S,^,^${DOCSDIR_REL}/,:ts\n' \
		              'PORTEXAMPLES:S,^,^${EXAMPLESDIR_REL}/,:ts\n' \
		              'PORTDATA:S,^,^${DATADIR_REL}/,:ts\n' \
		           -- WITH="$2" WITHOUT="$3") | /usr/bin/sed 's/\*/.*/g;s/\?/./g'
	) | /usr/bin/grep .)"
	# Filter .orig files unless requested
	$session.OptsFlags flags
	if $flags.check ORIG -eq 0; then
		filter="\\.orig\$
$filter"
	fi
	# Return the filter list
	$caller.setvar "$1" "$filter"
}

#
# Generates sed instructions from PLIST_SUB.
#
# @param &1
#	The variable to return the sub list to.
#
makeplist:BuildManager.plistSubSed() {
	local IFS vars sublist exprs sub prefix W
	IFS=$'\n'
	$($this.getSession).Vars vars
	$vars.get sublist PLIST_SUB:ts\\n
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
makeplist:BuildManager.create() {
	# Update linked list
	local build tail
	$this.getTail tail
	makeplist:Build build "$@"
	if makeplist:Build.isInstance "$tail"; then
		setvar ${tail}Next "$build"
	else
		setvar ${this}First "$build"
	fi
	setvar ${this}tail "$build"

	# Populate new list entry
	setvar ${build}retval "$1"
	setvar ${build}logfile "$2"
	setvar ${build}with "$3"
	setvar ${build}without "$4"
	$this.getSession ${build}session
	# Generate list of files
	local stagedir prefix mtree_file plistFilter
	$this.getStagedir stagedir
	$this.getPrefix prefix
	$this.getMtree_file mtree_file
	$this.plistFilter plistFilter "$3" "$4"
	setvar ${build}files "$( (
		/usr/bin/find "$stagedir" \( -type f -o -type l \) \
		              -not -path "$stagedir$prefix/*" 2>&- \
		| /usr/bin/sort -n \
		| /usr/bin/sed "s!^$stagedir!!"
		/usr/sbin/mtree -cp "$stagedir$prefix/" 2>&- \
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
makeplist:BuildManager.plist_filter() {
	/usr/bin/awk -f ${bsda_dir:-.}/makeplist_filter.awk "$@"
}

#
# Generate the packaging list.
#
# @param &1
#	The variable to return the plist to
#
makeplist:BuildManager.plist() {
	$caller.setvar "$1" "$(
		$this.getOptionsSorted options
		$this.plistSubSed subsed
		$this.First build
		while [ -n "$build" ]; do
			$build.getRetval retval
			# Skip failed builds
			if [ 0 -ne "$retval" ]; then
				$build.Next build
				continue
			fi
			$build.getWith with
			echo OPTIONS: $with
			$build.getFiles
			$build.Next build
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
	setvar ${this}dirname "$(/usr/bin/mktemp -d ${2:+-t "$2"})" || return $?
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
	/bin/rmdir "$dirname" 2>&- || :
}

#
# Manage build/stage attempts.
#
bsda:obj:createClass makeplist:Make \
	a:private:Logdir=makeplist:TmpDir \
	a:private:Builds=makeplist:BuildManager \
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
	origin="$(bsda:bsdmake -VPKGORIGIN)" || return $?
	if [ -z "$origin" ]; then
		$1.error "Port origin could not be detected"
		return 1
	fi
	wrkdir="$(bsda:bsdmake -VWRKDIR)" || return $?
	if ! /bin/mkdir -p "$wrkdir" 2>&-; then
		$1.error "The WRKDIR could not be created: $wrkdir"
		return 1
	fi
	if ! [ -w "$wrkdir" ]; then
		$1.error "The WRKDIR is not writable: $wrkdir"
		return 1
	fi
	$1.msg "Initialising make for $origin"
	origin="$(echo "$origin" | /usr/bin/tr / .)"
	file="$(bsda:bsdmake -VPLIST)" || return $?
	setvar ${this}plistOldFile "$file"
	test -z "$2" && setvar ${this}plistNewFile "$file.${0##*/}"
	$this.getPlistNewFile file
	if ! /usr/bin/touch "$file" 2>&-; then
		$1.error "The target plist-file is not writable: $file"
		return 1
	fi
	makeplist:TmpDir ${this}Logdir ${this}logdir "${0##*/}.$origin" \
	|| return $?
	makeplist:BuildManager ${this}Builds "$1" || return $?
	setvar ${this}no_build "$(bsda:bsdmake -VNO_BUILD)" || return $?
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
	local retval builds no_build stagedir prefix mtree_file
	local logdir logfilename opts logfile session oflags
	$this.getSession session
	$session.OptsFlags oflags
	$this.getLogdir logdir
	bsda:util:join opts - $1
	logfilename="$logdir/stage${opts:+-$opts}.log"
	makeplist:File logfile "$logfilename"
	$caller.delete $logfile
	$this.Builds builds
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
			     "$bsda_bsdmake" $targets WITH="$1" WITHOUT="$2" &
			wait $!
			return $?
		fi
		# Call make inside script:
		# - Call make inside script for logging
		# - Call port Makefile through interrupt.mk to send
		#   a signal back, if make is interrupted
		exec /usr/bin/script -aq "$logfilename" \
		     "$bsda_bsdmake" -f"${bsda_dir:-.}/interrupt.mk" \
		                     BSDA_PID=$$ $targets WITH="$1" WITHOUT="$2"
	)
	retval=$?

	# Collect return status and files
	$builds.create "$retval" "$logfilename.gz" "$@"

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
makeplist:Make.plist_keywords() {
	/usr/bin/awk -f ${bsda_dir:-.}/makeplist_keywords.awk "$@"
}

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
	local builds file plist origPlist change session
	$this.getSession session
	# Generate new plist
	$this.Builds builds
	$builds.plist plist
	if [ -z "$plist" ]; then
		$session.msg "The generated plist is empty"
		return 0
	fi
	# Get old plist
	$this.getPlistOldFile file
	if origPlist="$(/bin/cat "$file" 2>&-)"; then
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
	a:public:Vars=bsda:bsdmake:Vars \
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
	$1.usage usage "\t%.2s, %-13s  %s\n"
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
	bsda:opts:Flags ${this}OptsFlags || return $?
	bsda:bsdmake:Vars ${this}Vars || return $?
	$this.params "$@" || return $?
	$this.getOutfile outfile
	makeplist:Make ${this}Make $this "$outfile" || return $?
	makeplist:Options ${this}Options || return $?
	$this.run || return $?
}

#
# Parses the command line arguments.
#
# @param @
#	The command line arguments
#
makeplist:Session.params() {
	local IFS options flags option port vars var ignore

	bsda:opts:Options options \
	HELP        -h  --help        'Print usage and exit' \
	IGNORE_VARS -I* --ignore-vars 'A comma separated list of variables to ignore' \
	LICENSES    -l  --licenses    'Enable ports(7) license auditing framework' \
	ORIG        -O  --orig        'Include .orig files in the plist' \
	OUTFILE     -o* --outfile     'Set the output file for the new plist' \
	QUIET       -q  --quiet       'Suppress build output'
	$caller.delete $options

	$this.OptsFlags flags
	$this.Vars vars

	port=
	while [ $# -gt 0 ]; do
		$options.getopt option "$1"
		case "$option" in
		HELP)
			$this.help "$options"
			exit 0
		;;
		OUTFILE)
			local outfile
			if eval "[ -n \"\$${this}outfile\" ]"; then
				$this.error "More than one output file given: $2"
				return 1
			fi
			case "$1" in
			-o?*)
				outfile="${1#-o}"
			;;
			*)
				outfile="$2"
				shift
			;;
			esac
			case "$outfile" in
			/*)
				setvar ${this}outfile "$outfile"
			;;
			*)
				setvar ${this}outfile "$PWD/$outfile"
			;;
			esac
		;;
		IGNORE_VARS)
			case "$1" in
			-I?*)
				ignore="$ignore${1#-I},"
			;;
			*)
				ignore="$ignore$2,"
				shift
			;;
			esac
			IFS=,
			for var in $ignore; do case "$var" in
			DESKTOP_ENTRIES|USE_RC_SUBR|PLIST_FILES| \
			PORTDOCS|PORTEXAMPLES|PORTDATA|PLIST_SUB)
				# This is the list of allowed variables.
			;;
			*)
				$this.error "Ignoring make variable $var is not supported: $1"
				return 1
			;;
			esac; done
			$vars.ignore $ignore
		;;
		OPT_UNKNOWN)
			$this.error "Unknown parameter: \"$1\""
			return 1
		;;
		OPT_SPLIT)
			eval "$bsda_opts_split"
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
		portsdir="$(bsda:bsdmake -f/usr/share/mk/bsd.port.mk -VPORTSDIR)"
		port="$portsdir/$port"
	;;
	*)
		local portsdir origin
		portsdir="$(bsda:bsdmake -f/usr/share/mk/bsd.port.mk -VPORTSDIR)"
		origin="$(pkg:info:origins "$port")"
		if [ -z "$origin" ]; then
			$this.error "Cannot find port via \`pkg info\`: $port"
			return 1
		fi
		port="$portsdir/$origin"
	;;
	esac

	if [ -n "$port" ] && ! cd "$port" 2>&-; then
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
