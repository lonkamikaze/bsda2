test -n "$_makeplist_" && return 0
readonly _makeplist_=1

. ${bsda_dir:-.}/bsda_container.sh

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

makeplist:options:_in() {
	test -z "$1" && return 1
	local needle item 
	needle="$1"
	shift
	for item in "$@"; do
		test "$needle" = "$item" && return
	done
	return 1
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

bsda:obj:createClass makeplist:Plist \
	a:public:Next=makeplist:Plist \
	r:public:retval \
	r:public:with \
	r:public:without \
	r:public:files

bsda:obj:createClass makeplist:PlistManager \
	a:private:First=makeplist:Plist \
	r:private:tail \
	r:private:mtree_file \
	r:private:stagedir \
	r:private:prefix \
	r:private:_license_dir \
	r:private:desktopdir \
	r:private:plist_sub_sed \
	i:private:init \
	x:public:create \
	x:public:match

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
	setvar ${this}plist_sub_sed "$(/usr/bin/make -VPLIST_SUB_SED)" || return
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
	$this.getPlist_sub_sed plist_sub_sed
	setvar ${plist}retval "$1"
	setvar ${plist}with "$2"
	setvar ${plist}without "$3"
	setvar ${plist}files "$(
		/usr/sbin/mtree -cp "$stagedir$prefix/" \
		| /usr/sbin/mtree -Sf /dev/stdin -f "$mtree_file" \
		| /usr/bin/awk '/ (file|link) [^\/]*/{sub(/ (file|link) [^\/]*/, "");print}' \
		| /usr/bin/grep -v "^$_license_dir$nl^$desktopdir" \
		| /usr/bin/sort -n \
		| /usr/bin/sed "$plist_sub_sed")"
}

#
#
# @param &1
#	Files to add for this option
# @param &2
#	Files to remove for this option
# @param 3
#	The option to match
#
makeplist:PlistManager.match() {
	local plist with files firstMatch firstUnmatch retval
	local common match unmatch files
	$this.First plist
	firstMatch=1
	firstUnmatch=1
	common=
	match=
	unmatch=
	while makeplist:Plist.isInstance "$plist"; do
		$plist.getRetval retval
		# Skip failed builds
		if [ 0 -ne "$retval" ]; then
			$plist.Next plist
			continue
		fi
		$plist.getWith with
		# Get files
		if makeplist:options:_in "$3" $with; then
			# Files matching the option
			if [ -n "$firstMatch" ]; then
				firstMatch=
				$plist.getFiles match
			else
				$plist.getFiles files
				match="$(echo "$match" | /usr/bin/grep -Fx "$files")"
			fi
		else
			# Files matching anywhere but the option
			if [ -n "$firstUnmatch" ]; then
				firstUnmatch=
				$plist.getFiles unmatch
			else
				$plist.getFiles files
				unmatch="$(echo "$unmatch" | /usr/bin/grep -Fx "$files")"
			fi
		fi
		$plist.Next plist
	done
	files="$match"
	match="$(echo "$match" | /usr/bin/grep -vFx "$unmatch")"
	unmatch="$(echo "$unmatch" | /usr/bin/grep -vFx "$files")"
	$caller.setvar "$1" "$match"
	$caller.setvar "$2" "$unmatch"
}

bsda:obj:createClass makeplist:Make \
	a:private:Plists=makeplist:PlistManager \
	r:private:no_build \
	r:private:options \
	i:private:init \
	x:public:run \
	x:public:plist

makeplist:Make.init() {
	makeplist:PlistManager ${this}Plists || return
	setvar ${this}no_build "$(/usr/bin/make -VNO_BUILD)" || return
	setvar ${this}options "$(
		/usr/bin/make -V'SELECTED_OPTIONS:ts\n' \
		              -V'DESELECTED_OPTIONS:ts\n' \
		| /usr/bin/sort)" || return
}

makeplist:Make.run() {
	local retval plists no_build stagedir prefix mtree_file
	$this.Plists plists
	$this.getNo_build no_build
	if [ -n "$no_build" ]; then
		/usr/bin/make restage WITH="$1" WITHOUT="$2"
	else
		/usr/bin/make clean stage WITH="$1" WITHOUT="$2"
	fi
	$plists.create "$?" "$@"
}

makeplist:Make.plist() {
	local nl options option plists all null add remove mask
	nl='
'
	$this.Plists plists
	$this.getOptions options
	$plists.match null all ""
	for option in $options; do
		$plists.match add remove "$option"
		mask="$mask${mask:+${remove:+$nl}}$remove"
		add="$(echo "$add" | /usr/bin/sed "/./s/^/%%$option%%/")"
		remove="$(echo "$remove" | /usr/bin/sed "/./s/^/%%NO_$option%%/")"
		all="$all${all:+${add:+$nl}}$add"
		all="$all${all:+${remove:+$nl}}$remove"
	done

	# Filter files that show up as a %%NO_*%% somewhere
	local mask_sed
	mask_sed=h
	for option in $options; do
		mask_sed="$mask_sed;g;s/^/%%$option%%/p"
	done
	mask="$(echo "$mask" | /usr/bin/sed -n "$mask_sed")"
	all="$(echo "$all" | /usr/bin/grep -vFx "$mask")"

	$caller.setvar "$1" "$all"
}

bsda:obj:createClass makeplist:Session \
	a:private:Make=makeplist:Make \
	a:private:Flags=makeplist:options:Flags \
	a:private:Singles=makeplist:options:Singles \
	i:private:init \
	x:private:run

makeplist:Session.init() {
	makeplist:Make ${this}Make
	makeplist:options:Flags ${this}Flags
	makeplist:options:Singles ${this}Singles
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
