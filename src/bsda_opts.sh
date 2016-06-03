test -n "$_bsda_opts_" && return 0
readonly _bsda_opts_=1

. ${bsda_dir:-.}/bsda_container.sh

bsda:obj:createClass bsda:opts:Options \
	r:private:result \
	r:private:short \
	r:private:long \
	r:private:desc \
	r:private:next \
	i:private:init \
	c:private:clean \
	x:public:getopt \
	x:public:usage \
	x:public:append

bsda:opts:Options.init() {
	setvar ${this}result "$1"
	setvar ${this}short "$2"
	setvar ${this}long "$3"
	setvar ${this}desc "$4"
	unset ${this}next

	shift 4
	# Recursively create the next option
	if [ $# -gt 0 ]; then
		bsda:opts:Options ${this}next "$@"
	fi
}

bsda:opts:Options.clean() {
	local next
	$this.getNext next
	if [ -n "$next" ]; then
		$next.delete
	fi
}

bsda:opts:Options.getopt() {
	local result sopt lopt next retvar
	retvar="$1"
	shift
	$this.getShort sopt
	$this.getLong lopt
	$this.getResult result
	# Check argument against short option
	if [ -n "$sopt" -a -z "${1##${sopt}}" ]; then
		$caller.setvar "$retvar" "$result"
		return 0
	fi
	# Check argument against long option
	if [ -n "$lopt" -a -z "${1##${lopt}}" ]; then
		$caller.setvar "$retvar" "$result"
		return 0
	fi
	# Check argument against next option
	$this.getNext next
	if [ -n "$next" ]; then
		$next.getopt result "$@"
		$caller.setvar "$retvar" "$result"
		return 0
	fi
	# No options left
	if [ -n "$1" -a -z "${1##-?}" ]; then
		$caller.setvar "$retvar" OPT_UNKNOWN
		return 0
	fi
	if [ -n "$1" -a -z "${1##--*}" ]; then
		$caller.setvar "$retvar" OPT_UNKNOWN
		return 0
	fi
	if [ -n "$1" -a -z "${1##-*}" ]; then
		$caller.setvar "$retvar" OPT_SPLIT
		return 0
	fi
	$caller.setvar "$retvar" OPT_NOOPT
	return 1
}

bsda:opts:Options.usage() {
	local result next sopt lopt desc
	result=
	$this.getNext next
	if [ -n "$next" ]; then
		$next.usage result "$2"
	fi
	$this.getDesc desc
	if [ -n "$desc" ]; then
		$this.getShort sopt
		$this.getLong lopt
		result="$(printf "$2" "$sopt" "$lopt" "$desc")
$result"
	fi
	$caller.setvar "$1" "$result"
}

bsda:opts:Options.append() {
	local next
	$this.getNext next
	if [ -n "$next" ]; then
		$next.append "$@"
		return
	fi
	$class ${this}next "$@"
}

bsda:obj:createClass bsda:opts:Flags \
	bsda:container:Map r:private:flags "Flag counters" \
	i:private:init \
	c:private:clean \
	x:public:add \
	x:public:check

bsda:opts:Flags.init() {
	bsda:container:Map ${this}flags
}

bsda:opts:Flags.clean() {
	$($this.getFlags).delete
}

bsda:opts:Flags.add() {
	local flags value
	$this.getFlags flags
	$flags[ "$1" ] value
	value=$((value + 1))
	$flags[ "$1" ]= ${value}
}


bsda:opts:Flags.check() {
	local flags value
	$this.getFlags flags
	$flags[ "$1" ] value
	test $((value)) -eq $(($2))
}

