test -n "$_makeplist_" && return 0
readonly _makeplist_=1

. ${bsda_dir:-.}/bsda_container.sh

makeplist:_join() {
	local IFS
	IFS="$1"
	shift
	echo "$*"
}

makeplist:options:_pick() {
	local i
	i=$(($1))
	shift
	if [ $((i)) -ne 0 ]; then
		eval "echo \"\${$i}\""
	fi
}

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
# OPTIONS_DEFINE, OPTIONS_RADIO, OPTIONS_GROUP
#
bsda:obj:createClass makeplist:options:Flags \
	r:private:flags \
	r:private:select \
	i:private:init \
	x:public:next \
	x:public:with \
	x:public:without

makeplist:options:Flags.init() {
	local flags group
	flags="$(/usr/bin/make -VOPTIONS_DEFINE)"
	for group in $(/usr/bin/make -VOPTIONS_GROUP); do
		flags="${flags:+$flags }$(/usr/bin/make -VOPTIONS_GROUP_$group)"
	done
	for group in $(/usr/bin/make -VOPTIONS_RADIO); do
		flags="${flags:+$flags }$(/usr/bin/make -VOPTIONS_RADIO_$group)"
	done
	setvar ${this}select 0
	setvar ${this}flags "$flags"
}

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

makeplist:options:Flags.with() {
	local i flags
	$this.getSelect i
	$this.getFlags flags
	$caller.setvar "$1" "$(makeplist:options:_pick $i $flags)"
}

makeplist:options:Flags.without() {
	local i flags
	$this.getSelect i
	$this.getFlags flags
	$caller.setvar "$1" "$(makeplist:options:_except $i $flags)"
}

#
# OPTIONS_SINGLE, OPTIONS_MULTI
#
bsda:obj:createClass makeplist:options:Singles \
	a:private:Groups=bsda:container:Map \
	r:private:group \
	r:private:select \
	i:private:init \
	x:public:next \
	x:public:with \
	x:public:without

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

makeplist:options:Singles.next_lambda() {
	if [ -z "$group" ]; then
		group="$1"
		return 1
	fi
	if [ "$group" = "$1" ]; then
		group=
	fi
}

makeplist:options:Singles.next() {
	local groups group select options option complete
	complete=0
	$this.Groups groups
	$this.getGroup group
	$this.getSelect select
	$groups.[ "$group" ] options
	select=$((select + 1))
	option="$(makeplist:options:_pick $select $options)"
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

makeplist:options:Singles.with_lambda() {
	if [ "$group" == "$1" ]; then
		with="${with:+$with }$(makeplist:options:_pick $select $2)"
	else
		with="${with:+$with }$(makeplist:options:_pick 1 $2)"
	fi
}

makeplist:options:Singles.with() {
	local groups group select with
	$this.Groups groups
	$this.getGroup group
	$this.getSelect select
	with=
	$groups.foreach $class.with_lambda
	$caller.setvar "$1" "$with"
}

makeplist:options:Singles.without_lambda() {
	if [ "$group" == "$1" ]; then
		without="${without:+$without }$(makeplist:options:_except $select $2)"
	else
		without="${without:+$without }$(makeplist:options:_except 1 $2)"
	fi
}

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
	r:private:filename \
	i:private:init \
	c:private:clean

makeplist:File.init() {
	test -n "$1" || return
	setvar ${this}filename "$1"
}

makeplist:File.clean() {
	local filename
	$this.getFilename filename
	/bin/rm -f "$filename"
}

bsda:obj:createClass makeplist:Plist \
	a:public:Next=makeplist:Plist \
	r:public:retval \
	r:public:logfile \
	r:public:with \
	r:public:without \
	r:public:files \
	c:private:report

makeplist:Plist.report() {
	local retval with without logfile
	$this.getRetval retval
	# Skip successful builds
	test 0 -eq "$retval" && return 0
	$this.getWith with
	$this.getWithout without
	$this.getLogfile logfile
	echo "${0##*/}: ERROR: Building/staging returned $retval"
	echo "WITH=\"$with\""
	echo "WITHOUT=\"$without\""
	echo "A build log is available: $logfile"
}

bsda:obj:createClass makeplist:PlistManager \
	a:private:First=makeplist:Plist \
	r:private:tail \
	r:private:mtree_file \
	r:private:stagedir \
	r:private:prefix \
	r:private:_license_dir \
	r:private:desktopdir \
	r:private:optionsSorted \
	r:private:plistSubSed \
	x:private:plistSubSed \
	i:private:init \
	x:public:create \
	x:public:plist \
	x:public:report

makeplist:PlistManager.init() {
	local prefix
	setvar ${this}mtree_file "$(/usr/bin/make -VMTREE_FILE)" || return
	setvar ${this}stagedir "$(/usr/bin/make -VSTAGEDIR)" || return
	setvar ${this}prefix "$(/usr/bin/make -VPREFIX)" || return
	$this.getPrefix prefix
	setvar ${this}_license_dir "$(
		/usr/bin/make -V"_LICENSE_DIR:S,^$prefix/,,")" || return
	setvar ${this}desktopdir "$(
		/usr/bin/make -V"DESKTOPDIR:S,^$prefix/,,")" || return
	setvar ${this}optionsSorted "$(
		/usr/bin/make -V'SELECTED_OPTIONS:ts\n' \
		              -V'DESELECTED_OPTIONS:ts\n' \
		| /usr/bin/sort -n)" || return
	$this.plistSubSed || return
}

makeplist:PlistManager.plistSubSed() {
	local IFS sublist exprs sub
	IFS='
'
	sublist="$(/usr/bin/make -VPLIST_SUB:ts\\n)" || return
	# Sort by replacement size so the biggest mach wins
	sublist="$(
		for sub in $sublist; do
			tail="${sub#*=}"
			tail="${tail#\"}";tail="${tail%\"}"
			case "$tail" in
			''|@*)
				continue
			;;
			esac
			tail="$(echo -n "$tail" | /usr/bin/vis -ce '.[]*?!')"
			echo "${#tail} ${sub%%=*}=$tail"
		done | /usr/bin/sort -rn | /usr/bin/sed 's/^[0-9]* //'
	)"
	#
	exprs=
	for sub in $sublist; do case "$sub" in
	LIB32DIR=*)
	;;
	*DIR=*)
		exprs="${exprs}s!${sub#*=}/!%%${sub%%=*}%%/!;"
	;;
	*VER=*|*VERSION=*)
		exprs="${exprs}s!${sub#*=}!%%${sub%%=*}%%!;"
	esac; done
	setvar ${this}plistSubSed "$exprs"
}

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
	local nl _license_dir desktopdir stagedir prefix mtree_file
	local plist_sub_sed
	nl='
'
	$this.get_license_dir _license_dir
	$this.getDesktopdir desktopdir
	$this.getStagedir stagedir
	$this.getPrefix prefix
	$this.getMtree_file mtree_file
	setvar ${plist}retval "$1"
	setvar ${plist}logfile "$2"
	setvar ${plist}with "$3"
	setvar ${plist}without "$4"
	setvar ${plist}files "$(
		/usr/sbin/mtree -cp "$stagedir$prefix/" \
		| /usr/sbin/mtree -Sf /dev/stdin -f "$mtree_file" \
		| /usr/bin/awk '/ (file|link) [^\/]*/{sub(/ (file|link) [^\/]*/, "");print}' \
		| /usr/bin/grep -v "^$_license_dir$nl^$desktopdir")"
}

makeplist:PlistManager.plist_filter() { /usr/bin/awk '
	# Get the order of options
	BEGIN {
		for (i = 1; i < ARGC; ++i) {
			OPTIONS_ORDERD[i] = ARGV[i]
			CNT_OPT_FILES[ARGV[i]] = 0
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
				if (OPT_FILES[option, file] == FILES[file]) {
					print "%%" option "%%" file
					delete FILES[file]
				}
				# Print file if it occurs everywhere but with
				# this option
				else if (!OPT_FILES[option, file] && \
				         FILES[file] + OPTIONS[option] == CONFIGS) {
					print "%%NO_" option "%%" file
					delete FILES[file]
				}
			}
		}
		# Print all files that have not been printed
		for (i = 1; i <= CNT_FILES; ++i) {
			file = FILES_ORDERED[i]
			if (!(file in FILES)) { continue }
			print "@fail " file " could not be mapped to an option!"
		}
	}
' "$@";}

makeplist:PlistManager.plist() {
	$caller.setvar "$1" "$(
		$this.getOptionsSorted options
		$this.getPlistSubSed subsed
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
		done | $class.plist_filter $options | /usr/bin/sed "$subsed"
	)"
}

#
# Creates a temporary directory.
#
bsda:obj:createClass makeplist:TmpDir \
	r:private:dirname \
	i:private:init \
	c:private:clean

#
# @param &1
#	The variable to return the dirname to
# @param 2
#	The mktemp template
#
makeplist:TmpDir.init() {
	setvar ${this}dirname "$(/usr/bin/mktemp -d ${2:+-t "$2"})" || return
	local dirname
	$this.getDirname dirname
	$caller.setvar "$1" "$dirname"
}

makeplist:TmpDir.clean() {
	local dirname
	$this.getDirname dirname
	/bin/rmdir "$dirname" 2> /dev/null || :
}

bsda:obj:createClass makeplist:Make \
	a:private:Logdir=makeplist:TmpDir \
	a:private:Plists=makeplist:PlistManager \
	r:private:logdir \
	r:private:no_build \
	i:private:init \
	x:public:run \
	x:public:plist

makeplist:Make.init() {
	local origin
	origin="$(/usr/bin/make -VPKGORIGIN:S,/,.,g)" || return
	if [ -z "$origin" ]; then
		echo "${0##*/}: ERROR: Port origin could not be detected"
		return 1
	fi
	makeplist:TmpDir ${this}Logdir ${this}logdir "${0##*/}.$origin" \
	|| return
	makeplist:PlistManager ${this}Plists || return
	setvar ${this}no_build "$(/usr/bin/make -VNO_BUILD)" || return
}

makeplist:Make.run() {
	local retval plists no_build stagedir prefix mtree_file
	local retval logdir logfilename logfile
	$this.getLogdir logdir
	logfilename="$logdir/stage${1:+-$(makeplist:_join - $1)}.log"
	makeplist:File logfile "$logfilename"
	$caller.delete $logfile
	$this.Plists plists
	$this.getNo_build no_build
	if [ -n "$no_build" ]; then
		/usr/bin/script -q "$logfilename" \
		                /usr/bin/make restage WITH="$1" WITHOUT="$2"
	else
		/usr/bin/script -q "$logfilename" \
		                /usr/bin/make clean stage WITH="$1" WITHOUT="$2"
	fi
	retval=$?
	if [ 0 -ne $retval ]; then
		/usr/bin/gzip -9 "$logfilename"
	fi
	$plists.create "$retval" "$logfilename.gz" "$@"
}

makeplist:Make.plist() {
	local plists plist
	$this.Plists plists
	$plists.plist plist
	$caller.setvar "$1" "$plist"
}

bsda:obj:createClass makeplist:Session \
	a:private:Make=makeplist:Make \
	a:private:Flags=makeplist:options:Flags \
	a:private:Singles=makeplist:options:Singles \
	i:private:init \
	x:private:run

makeplist:Session.init() {
	makeplist:Make ${this}Make || return
	makeplist:options:Flags ${this}Flags || return
	makeplist:options:Singles ${this}Singles || return
	$this.run
}

makeplist:Session.run() {
	local make flags singles option with without count i
	$this.Make make
	$this.Flags flags
	$this.Singles singles

	count=1
	while $flags.next; do
		count=$((count + 1))
	done
	while $singles.next; do
		count=$((count + 1))
	done
	
	$flags.with with
	$flags.without without
	$singles.with option
	with="$with${with:+${option:+ }}$option"
	$singles.without option
	without="$without${without:+${option:+ }}$option"
	echo "${0##*/}: Building plist $((i = 1)) of $count${with:+: $with}"
	$make.run "$with" "$without"
	while $flags.next; do
		$flags.with with
		$flags.without without
		$singles.with option
		with="$with${with:+${option:+ }}$option"
		$singles.without option
		without="$without${without:+${option:+ }}$option"
		echo "${0##*/}: Building plist $((i += 1)) of $count: $with"
		$make.run "$with" "$without"
	done
	while $singles.next; do
		$flags.with with
		$flags.without without
		$singles.with option
		with="$with${with:+${option:+ }}$option"
		$singles.without option
		without="$without${without:+${option:+ }}$option"
		echo "${0##*/}: Building plist $((i += 1)) of $count: $with"
		$make.run "$with" "$without"
	done
	echo "${0##*/}: Printing to pkg-plist.${0##*/}"
	$make.plist | /usr/bin/tee "pkg-plist.${0##*/}"
}
