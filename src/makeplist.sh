test -n "$_makeplist_" && return 0
readonly _makeplist_=1

. ${bsda_dir:-.}/bsda_container.sh
. ${bsda_dir:-.}/pkg_info.sh
. ${bsda_dir:-.}/bsda_opts.sh

#
# A static function that outputs all arguments joined by a given
# separator.
#
# @param 1
#	The separator character
# @param *
#	The arguments to join
#
makeplist:_join() {
	local IFS
	IFS="$1"
	shift
	echo "$*"
}

#
# From a list of arguments pick the argument with the given number,
# counting from 1.
#
# @param 1
#	The index of the desired argument
# @param @
#	The list of items
#
makeplist:options:_pick() {
	local i
	i=$(($1))
	shift
	if [ $((i)) -ne 0 ]; then
		eval "echo \"\${$i}\""
	fi
}

#
# Outputs all but the selected argument.
#
# @param 1
#	The index of the undesired argument
# @param @
#	The list of items
#
makeplist:options:_except() {
	local i item
	i=$(($1))
	shift
	for item in "$@"; do
		shift
		if [ $((i -= 1)) -ne 0 ]; then
			set -- "$@" "$item"
		fi
	done
	echo "$*"
}

#
# Instances permute through binary options.
#
# This handles the following kinds of options:
#
# - `OPTIONS_DEFINE`
# - `OPTIONS_RADIO`
# - `OPTIONS_GROUP`
#
# These kinds of options are basically independent flags, only grouped
# for usability purposes.
#
# Instead of permuting through all valid combinations, only use each
# option once. All permutations would be in O(n!), which is exponential
# growth and hence problematic for even a small amount of options.
#
bsda:obj:createClass makeplist:options:Flags \
	r:private:flags  "All options to permute through" \
	r:private:select "The index of the currently selected flag" \
	i:private:init   "Acquire all flags from make" \
	x:public:next    "Select the next permutation" \
	x:public:with    "List the flag activated for this permutation" \
	x:public:without "List flags not activated for this permutation"

#
# Acquire all flags from make.
#
makeplist:options:Flags.init() {
	local flags group
	flags="$(/usr/bin/make -VOPTIONS_DEFINE)" || return
	for group in $(/usr/bin/make -VOPTIONS_GROUP); do
		flags="${flags:+$flags }$(/usr/bin/make -VOPTIONS_GROUP_$group)" \
		|| return
	done
	for group in $(/usr/bin/make -VOPTIONS_RADIO); do
		flags="${flags:+$flags }$(/usr/bin/make -VOPTIONS_RADIO_$group)" \
		|| return
	done
	setvar ${this}select 0
	setvar ${this}flags "$flags"
}

#
# Select the next permutation.
#
# Selects the next flag. Starts over after going through all flags.
#
# @retval 0
#	Selecting the next flag succeeded
# @retval 1
#	No more flags left, starting over
#
makeplist:options:Flags.next() {
	local i flags flag
	$this.getSelect i
	setvar ${this}select $((i += 1))
	$this.getFlags flags
	flag="$(makeplist:options:_pick $i $flags)"
	if [ -z "$flag" ]; then
		setvar ${this}select 0
		return 1
	fi
}

#
# Returns the selected flag.
#
# @param &1
#	The variable to return the flag to
#
makeplist:options:Flags.with() {
	local i flags
	$this.getSelect i
	$this.getFlags flags
	$caller.setvar "$1" "$(makeplist:options:_pick $i $flags)"
}

#
# Returns all but the selected flag.
#
# @param &1
#	The variable to return the flags to.
#
makeplist:options:Flags.without() {
	local i flags
	$this.getSelect i
	$this.getFlags flags
	$caller.setvar "$1" "$(makeplist:options:_except $i $flags)"
}

#
# Instances permute through single and multi option groups.
#
# This handles the following kinds of options:
#
# - `OPTIONS_SINGLE`
# - `OPTIONS_MULTI`
#
# Of each group of options one has to be selected. This permutation
# makes sure every option is selected at least once.
#
bsda:obj:createClass makeplist:options:Singles \
	a:private:Groups=bsda:container:Map \
	r:private:group  "The currently selected group" \
	r:private:select "The index of the option selected from the group" \
	i:private:init   "Acquire option groups from make" \
	x:public:next    "Select the next option" \
	x:public:with    "The selected option of every group" \
	x:public:without "The options not selected"

#
# Acquire all option groups from make.
#
makeplist:options:Singles.init() {
	bsda:container:Map ${this}Groups
	local group groups
	$this.Groups groups
	for group in $(/usr/bin/make -VOPTIONS_SINGLE); do
		$groups.[ $group ]= "$(/usr/bin/make -VOPTIONS_SINGLE_$group)"
	done
	for group in $(/usr/bin/make -VOPTIONS_MULTI); do
		$groups.[ $group ]= "$(/usr/bin/make -VOPTIONS_MULTI_$group)"
	done
	setvar ${this}select 1
}

#
# Iterates through the map of groups until the group following the
# current selection is found.
#
# @param group
#	Must be set to current group, returns set to the next group
# @param 1,2
#	The group and its options
# @retval 0
#	Iterated beyond the last group
# @retval 1
#	The next group has been selected
#
makeplist:options:Singles.next_lambda() {
	if [ -z "$group" ]; then
		group="$1"
		return 1
	fi
	if [ "$group" = "$1" ]; then
		group=
	fi
}

#
# Select the next permutation.
#
# Select the next option. Starts over after going through all options.
#
# @retval 0
#	Selecting the next option succeeded
# @retval 1
#	No more option left, starting over
#
makeplist:options:Singles.next() {
	local groups group select options option complete
	complete=0
	$this.Groups groups
	$this.getGroup group
	$this.getSelect select
	# Select the next option
	$groups.[ "$group" ] options
	select=$((select + 1))
	option="$(makeplist:options:_pick $select $options)"
	# If no option is left in the group select the next group
	if [ -z "$option" ]; then
		select=2
		if $groups.foreach $class.next_lambda; then
			complete=1
		fi
	fi
	setvar ${this}group "$group"
	setvar ${this}select "$select"
	return $complete
}

#
# Accumulates selected options from the map of groups.
#
# @param group,select
#	Must be set to current group and selection index
# @param with
#	Accumulates the selected options
# @param 1,2
#	The group and its options
#
makeplist:options:Singles.with_lambda() {
	if [ "$group" = "$1" ]; then
		with="${with:+$with }$(makeplist:options:_pick $select $2)"
	else
		with="${with:+$with }$(makeplist:options:_pick 1 $2)"
	fi
}

#
# Returns the selected options.
#
# @param &1
#	The variable to return the options to
#
makeplist:options:Singles.with() {
	local groups group select with
	$this.Groups groups
	$this.getGroup group
	$this.getSelect select
	with=
	$groups.foreach $class.with_lambda
	$caller.setvar "$1" "$with"
}

#
# Accumulates unselected options from the map of groups.
#
# @param group,select
#	Must be set to current group and selection index
# @param without
#	Accumulates the unselected options
# @param 1,2
#	The group and its options
#
makeplist:options:Singles.without_lambda() {
	if [ "$group" = "$1" ]; then
		without="${without:+$without }$(makeplist:options:_except $select $2)"
	else
		without="${without:+$without }$(makeplist:options:_except 1 $2)"
	fi
}

#
# Returns everything but the selected options.
#
# @param &1
#	The variable to return the options to
#
makeplist:options:Singles.without() {
	local groups group select without
	$this.Groups groups
	$this.getGroup group
	$this.getSelect select
	without=
	$groups.foreach $class.without_lambda
	$caller.setvar "$1" "$without"
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
	$session.error "Building/staging returned $retval"
	echo "WITH=\"$with\""
	echo "WITHOUT=\"$without\""
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
	local logdir logfilename logfile session oflags
	$this.getSession session
	$session.OptsFlags oflags
	$this.getLogdir logdir
	logfilename="$logdir/stage${1:+-$(makeplist:_join - $1)}.log"
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
		# Close outputs in quiet mode
		if $oflags.check QUIET -ne 0; then
			export BATCH=1
			exec 2>&- >&-
		fi
		# Disable license features unless specifically requested
		if $oflags.check LICENSES -eq 0; then
			export DISABLE_LICENSES=1
		fi
		# Call make inside script:
		# - Call make inside script for logging
		# - Call port Makefile through interrupt.mk to send
		#   a signal back, if make is interrupted
		exec /usr/bin/script -q "$logfilename" \
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
	echo -n "$plist" > "$file"

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
	a:private:Flags=makeplist:options:Flags \
	a:private:Singles=makeplist:options:Singles \
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
	makeplist:options:Flags ${this}Flags || return
	makeplist:options:Singles ${this}Singles || return
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
			$this.error "Unknown parameter \"$1\"."
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
	local make flags singles option with without count i
	$this.Make make
	$this.Flags flags
	$this.Singles singles

	# Go through all permutations to count them
	count=1
	while $flags.next; do
		count=$((count + 1))
	done
	while $singles.next; do
		count=$((count + 1))
	done

	#
	# Run make for each permutation
	#

	# Get the initial state with no flags and all singles set
	# to the first option
	$flags.with with
	$flags.without without
	$singles.with option
	with="$with${with:+${option:+ }}$option"
	$singles.without option
	without="$without${without:+${option:+ }}$option"
	$this.msg "Building plist $((i = 1)) of $count${with:+: $with}"
	$make.run "$with" "$without"

	# Try all flags
	while $flags.next; do
		$flags.with with
		$flags.without without
		$singles.with option
		with="$with${with:+${option:+ }}$option"
		$singles.without option
		without="$without${without:+${option:+ }}$option"
		$this.msg "Building plist $((i += 1)) of $count: $with"
		$make.run "$with" "$without"
	done

	# Try every single/multi flag once
	while $singles.next; do
		$flags.with with
		$flags.without without
		$singles.with option
		with="$with${with:+${option:+ }}$option"
		$singles.without option
		without="$without${without:+${option:+ }}$option"
		$this.msg "Building plist $((i += 1)) of $count: $with"
		$make.run "$with" "$without"
	done

	# Generate the resulting plist
	$make.plist
}
