test -n "$_bsda_opts_" && return 0
readonly _bsda_opts_=1

. ${bsda_dir:-.}/bsda_container.sh

#
# This package provides bsda:opts:Options to share subsets of command line
# options across scripts and bsd:opts:Flags to handle simple flags, whose
# occurrence just needs to be counted.
#
# The following example shows how to check for a bunch of options and count
# them as flags:
#
#	$options.getopt option "$1"
#	case "$option" in
#	PKG_* | VERBOSE)
#		$flags.add "$option"
#	;;
#	...
#	esac
#
# This example shows how to check a flag.
#
#	if $flags.check VERBOSE -ne 0; then
#		echo "Starting in verbose mode" 1>&2
#	fi
#

#
# This class provides a growable collection of command line options.
#
# Command line arguments can be passed to the getopt() method and an
# identifier for the first match is returned.
#
# There are some hard coded identifiers:
#
# | Identifier  | Description                                                 |
# |-------------|-------------------------------------------------------------|
# | OPT_UNKNOWN | An undefined option was encountered                         |
# | OPT_SPLIT   | The argument is a chain of options that need to be split up |
# | OPT_NOOPT   | The argument is not an option                               |
#
bsda:obj:createClass bsda:opts:Options \
	a:private:Next=bsda:opts:Options \
	r:private:ident  "The identifier to return for a match" \
	r:private:short  "The short version of the option" \
	r:private:long   "The long version of the option" \
	r:private:desc   "The description for the usage output" \
	i:private:init   "The constructor" \
	x:public:getopt  "Checks the given argument against the options" \
	x:public:usage   "Returns options and descriptions" \
	x:public:append  "Grow the collection"

#
# The constructor creates a linked list of options.
#
# @param 1
#	The identifier to return for this option, e.g. `HELP`
# @param 2
#	The short version of this option, e.g. `-h`
# @param 3
#	The long version of this option, e.g. `--help`
# @param 4
#	The description for this option
# @param @
#	More tuples defining options
#
bsda:opts:Options.init() {
	setvar ${this}ident "$1"
	setvar ${this}short "$2"
	setvar ${this}long "$3"
	setvar ${this}desc "$4"

	shift 4
	# Recursively create the next option
	if [ $# -gt 0 ]; then
		bsda:opts:Options ${this}Next "$@"
	fi
}

#
# Recursively check the given argument against the collection of options.
#
# @param &1
#	The variable to return the option identifier to
# @param 2
#	The command line argument to check
#
bsda:opts:Options.getopt() {
	local ident sopt lopt next retvar
	retvar="$1"
	shift
	$this.getShort sopt
	$this.getLong lopt
	$this.getIdent ident
	# Check argument against short option
	if [ -n "$sopt" ] && [ -z "${1##${sopt}}" ]; then
		$caller.setvar "$retvar" "$ident"
		return 0
	fi
	# Check argument against long option
	if [ -n "$lopt" ] && [ -z "${1##${lopt}}" ]; then
		$caller.setvar "$retvar" "$ident"
		return 0
	fi
	# Check argument against next option
	$this.Next next
	if [ -n "$next" ]; then
		$next.getopt ident "$@"
		$caller.setvar "$retvar" "$ident"
		return 0
	fi
	# No options left
	if [ -n "$1" ] && [ -z "${1##-?}" ]; then
		$caller.setvar "$retvar" OPT_UNKNOWN
		return 0
	fi
	if [ -n "$1" ] && [ -z "${1##--*}" ]; then
		$caller.setvar "$retvar" OPT_UNKNOWN
		return 0
	fi
	if [ -n "$1" ] && [ -z "${1##-*}" ]; then
		$caller.setvar "$retvar" OPT_SPLIT
		return 0
	fi
	$caller.setvar "$retvar" OPT_NOOPT
	return 1
}

#
# Returns a formatted string containing all the options and there
# descriptions.
#
# Options occur in the order of definition, options without a description
# are not listed.
#
# @param &1
#	The variable to store the resulting string in
# @param 2
#	A printf style formatting string, the first argument will be the
#	short option, the second the long option and the third the
#       description
#
bsda:opts:Options.usage() {
	local next sopt lopt desc
	result=
	$this.Next next
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

#
# Grow the list of options.
#
# This method allows patching one set of options together from different
# collections.
#
# @param @
#	See the init() constructor
#
bsda:opts:Options.append() {
	local next
	$this.Next next
	if [ -n "$next" ]; then
		$next.append "$@"
		return $?
	fi
	$class ${this}Next "$@"
}

#
# A simple container to hold flag occurrence counts.
#
bsda:obj:createClass bsda:opts:Flags \
	a:private:Flags=bsda:container:Map \
	i:private:init  "The constructor" \
	x:public:add    "Count the given flag" \
	x:public:check  "Compare a flag numerically"

#
# The constructor initialises an empty map.
#
bsda:opts:Flags.init() {
	bsda:container:Map ${this}Flags
}

#
# Count the given flag.
#
# @param 1
#	The flag to count
#
bsda:opts:Flags.add() {
	local flags value
	$this.Flags flags
	$flags.[ "$1" ] value
	value=$((value + 1))
	$flags.[ "$1" ]= ${value}
}

#
# Perform numerical comparison with a flag.
#
# This method takes a flag, a test-style numerical operator (like
# -eq) and a numerical value.
#
# Uncounted flags compare -eq 0.
#
# @param 1
#	The flag to check the count of
# @param 2
#	The numerical comparison operator
# @param 3
#	The numerical value
# @retval 0
#	The comparison statement is true
# @retval 1
#	The comparison statement is false
#
bsda:opts:Flags.check() {
	local flags value
	$this.Flags flags
	$flags.[ "$1" ] value
	test $((value)) "$2" $(($3))
}
