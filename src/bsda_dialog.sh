test -n "$_bsda_dialog_" && return 0
readonly _bsda_dialog_=1

. ${bsda_dir:-.}/bsda_obj.sh

#
# Provides a slim wrapper around dialog(1).
#

#
# A slim wrapper around dialog(1).
#
bsda:obj:createClass bsda:dialog:Dialog \
	r:private:desc     "A file descriptor used when calling dialog(1)" \
	r:private:args     "Additional arguments to dialog(1)" \
	i:private:init     "The constructor" \
	c:private:clean    "The destructor" \
	x:private:call     "Perform a call to dialog(1)" \
	x:public:setArgs   "Set additional arguments to dialog(1)" \
	x:public:checklist "Call dialog --checklist" \
	x:public:menu      "Call dialog --menu" \
	x:public:msgbox    "Call dialog --msgbox"

#
# The constructor.
#
# Sets up a file descriptor to route dialog's use of stdout around
# the variable assignment that catches the output of dialog.
#
# Construction fails if no more file descriptors are available.
#
# @param @
#	Additional arguments to dialog, see dialog(1)
#
bsda:dialog:Dialog.init() {
	local desc
	bsda:obj:getDesc desc || return
	setvar ${this}desc "$desc"
	eval "exec $desc>&1"
	$this.setArgs "$@"
}

#
# The destructor.
#
# Closes and releases the file descriptor.
#
bsda:dialog:Dialog.clean() {
	local desc
	$this.getDesc desc
	eval "exec $desc>&-"
	bsda:obj:releaseDesc "$desc"
}

#
# Perform a call to dialog(1) catching and returning its output.
#
# @param &1
#	The variable to return the output to
# @param @
#	The arguments to the dialog call
# @return
#	See dialog(1)
#
bsda:dialog:Dialog.call() {
	local ret result
	result="$(
		$this.getArgs args
		$this.getDesc desc
		shift
		(/usr/bin/dialog $args --backtitle "${0##*/}" "$@" \
		                 >&$desc ) 2>&1)"
	ret=$?
	$caller.setvar "$1" "$result"
	return $ret
}

#
# Set additional arguments to dialog(1).
#
# @param @
#	Arguments to use for following dialog(1) calls
#
bsda:dialog:Dialog.setArgs() {
	local IFS
	IFS='
'
	setvar ${this}args "$*"
}

#
# Creates a checklist.
#
# @param &1
#	The variable to return dialog's output to
# @param 2
#	The checklist label
# @param @
#	[ tag item status ] …
# @return
#	See dialog(1)
#
bsda:dialog:Dialog.checklist() {
	local retvar text result
	retvar="$1"
	text="$2"
	shift 2
	$this.call result --separate-output --checklist "$text" 0 0 0 "$@"
	ret=$?
	$caller.setvar "$retvar" "$result"
	return $ret
}

#
# Creates a menu.
#
# @param &1
#	The variable to return dialog's output to
# @param 2
#	The menu label
# @param @
#	[ tag item ] …
# @return
#	See dialog(1)
#
bsda:dialog:Dialog.menu() {
	local retvar text result
	retvar="$1"
	text="$2"
	shift 2
	$this.call result --menu "$text" 0 0 0 "$@"
	ret=$?
	$caller.setvar "$retvar" "$result"
	return $ret
}

#
# Creates a msgbox.
#
# @param &1
#	The variable to return dialog's output to
# @param 2
#	The text
#
bsda:dialog:Dialog.msgbox() {
	$class.call "$1" --msgbox "$2" 0 0
}
