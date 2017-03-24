test -n "$_bsda_bsdmake_" && return 0
readonly _bsda_bsdmake_=1

#
# The BSD make binary, this can be overridden.
#
: ${bsda_bsdmake:=/usr/bin/make}

#
# Alias for the make executable.
#
# @param @
#	Arguments to make
# @return
#	The return value of make
#
bsda:bsdmake() {
	"$bsda_bsdmake" "$@"
}

#
# Instances retrieve variable values from make.
#
# The added benefit is that this can be fed a list of variables that
# should be ignored.
#
bsda:obj:createClass bsda:bsdmake:Vars \
	r:private:ignore "The list of make variables to ignore" \
	x:public:ignore  "Add to the list of make variables to ignore" \
	x:public:get     "Retrieve make variables"

#
# Adds all arguments to the list of make variables to ignore.
#
# @param *
#	The make variables to ignore
#
bsda:bsdmake:Vars.ignore() {
	local IFS ignore
	IFS=$'\n'
	$this.getIgnore ignore
	setvar ${this}ignore "$ignore$*$IFS"
}

#
# Retrieve the requested make variables not in the ignore list.
#
# The retrieval definition contains of a list of variables to retrieve
# and optionally a list of vanilla arguments to make.
#
# All arguments following the first -- are passed on to make as provided.
#
# All other arguments are treated as make variables. Every argument
# must start with the name of a make variable, but may make use of
# the : modifiers. Please note that every variable definition is
# quoted with ', so the use of ' inside of modifiers should be avoided
# or escaped very carefully.
#
# @param &1
#	The destination variable for the make output
# @param @
#	The retrieval definition
#
bsda:bsdmake:Vars.get() {
	$caller.setvar "$1" "$(
		shift
		$this.getIgnore ignore
		args=
		for arg in "$@"; do shift; case "$arg" in
		--)
			break
		;;
		*)
			if echo "$ignore" | /usr/bin/grep -qFx "${arg%%:*}"; then
				continue
			fi
			args="$args -V'\${$arg}'"
		;;
		esac; done
		eval "bsda:bsdmake $args \"\$@\""
	)"
}
