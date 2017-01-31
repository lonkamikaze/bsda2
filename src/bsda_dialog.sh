test -n "$_bsda_dialog_" && return 0
readonly _bsda_dialog_=1

. ${bsda_dir:-.}/bsda_obj.sh

bsda:obj:createClass bsda:dialog:Dialog \
	r:private:args \
	i:private:init \
	x:private:call \
	x:public:setArgs \
	x:public:checklist \
	x:public:menu \
	x:public:msgbox

bsda:dialog:Dialog.init() {
	test -w /dev/tty || return
	$this.setArgs "$@"
}

bsda:dialog:Dialog.call() {
	local ret result
	result="$(
		$this.getArgs args
		shift
		(/usr/bin/dialog $args --backtitle "${0##*/}" "$@" \
		                 > /dev/tty ) 2>&1
	)"
	ret=$?
	$caller.setvar "$1" "$result"
	return $ret
}

bsda:dialog:Dialog.setArgs() {
	local IFS
	IFS='
'
	setvar ${this}args "$*"
}

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

bsda:dialog:Dialog.msgbox() {
	$class.call "$1" --msgbox "$2" 0 0
}
