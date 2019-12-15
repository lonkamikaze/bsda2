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
# This class provides a growable forward list of command line options.
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
# This class should be utilised by creating an instance of bsda:opts:Options.
#
bsda:obj:createClass bsda:opts:Option \
	a:private:Next=bsda:opts:Option \
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
# @retval 0
#	Creating options succeeded
# @retval 1
#	Failure due to incomplete tuples
#
bsda:opts:Option.init() {
	setvar ${this}ident "$1"
	setvar ${this}short "$2"
	setvar ${this}long "$3"
	setvar ${this}desc "$4"

	shift 4 || return 1
	# Recursively create the next option
	if [ $# -gt 0 ]; then
		bsda:opts:Option ${this}Next "$@"
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
bsda:opts:Option.getopt() {
	local ident sopt lopt next retvar ret
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
		ret=$?
		$caller.setvar "$retvar" "$ident"
		return $ret
	fi
	# No options left
	case "$1" in
	-?|--?*)
		$caller.setvar "$retvar" OPT_UNKNOWN
	;;
	-??*)
		$caller.setvar "$retvar" OPT_SPLIT
	;;
	*)
		$caller.setvar "$retvar" OPT_NOOPT
		return 1
	;;
	esac
	return 0
}

#
# Returns a formatted string containing all the options and their
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
bsda:opts:Option.usage() {
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
bsda:opts:Option.append() {
	local next
	$this.Next next
	if [ -n "$next" ]; then
		$next.append "$@"
		return $?
	fi
	$class ${this}Next "$@"
}

#
# Manages a linked list of Option instances.
#
# The one difference using this wrapper makes is that an empty instance
# without any options can be created.
#
bsda:obj:createClass bsda:opts:Options \
	a:private:First=bsda:opts:Option \
	i:private:init  "The constructor" \
	x:public:getopt "Wrapper around bsda:opts:Option.getopt()" \
	x:public:usage  "Wrapper around bsda:opts:Option.usage()" \
	x:public:append "Wrapper around bsda:opts:Option.append()"

#
# Creates the linked list of options.
#
# @param @
#	If given arguments are passed to bsda:opts:Option
#
bsda:opts:Options.init() {
	if [ $# -gt 0 ]; then
		bsda:opts:Option ${this}First "$@"
	fi
}

#
# Calls bsda:opts:Option.getopt().
#
# @retval 2
#	If no options have been defined
#
bsda:opts:Options.getopt() {
	local first
	$this.First first
	if [ -n "$first" ]; then
		$first.getopt "$@"
		return $?
	fi
	return 2
}

#
# Calls bsda:opts:Option.usage().
#
# @retval 2
#	If no options have been defined
#
bsda:opts:Options.usage() {
	local first
	$this.First first
	if [ -n "$first" ]; then
		$first.usage "$@"
		return $?
	fi
	return 2
}

#
# Creates or appends to the list of options.
#
# @see bsda:opts:Option.append()
#
bsda:opts:Options.append() {
	local first
	$this.First first
	if [ -n "$first" ]; then
		$first.append "$@"
		return $?
	fi
	bsda:opts:Option ${this}First "$@"
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
# Supports creating an initial list of flag counts taking the following
# forms:
#
# - `'%s' flag`:
#   Initialise from environment (undefined = 0)
# - `'%s=%s' flag value`:
#   Initialise with the given boolean or unsigned integer value
# - `'%s?=%s' flag value`:
#   Initialise from environment, fall back to the given value if the
#   environment variable is undefined
#
# Values may be boolean or unsigned integer values, boolean values
# are interpreted as either 1 or 0:
#
# | Symbol | Value | Comment          |
# |--------|-------|------------------|
# | yes    | 1     | Case insensitive |
# | true   | 1     | "                |
# | no     | 0     | "                |
# | false  | 0     | "                |
# | ''     | 0     | The empty string |
#
# Invalid values are ignored.
#
# @param @
#	A list of initial value assignments
#
bsda:opts:Flags.init() {
	# Create map for flags
	bsda:container:Map ${this}Flags

	# Initialise the map
	local IFS flags flag var value
	$this.Flags flags
	IFS=$'\n'
	for flag in "$@"; do
		# Get var and value
		case "$flag" in
		*\?=*)  # Assign given value unless env provides one
			var="${flag%%\?=*}"
			if ! value="$(/usr/bin/printenv "${flag%%\?=*}")"; then
				value="${flag#*\?=}"
			fi
		;;
		*=*)    # Assign given value unconditionally
			var="${flag%%=*}"
			value="${flag#*=}"
		;;
		*)      # Get value from environment
			var="$flag"
			value="$(/usr/bin/printenv "$flag")"
		;;
		esac

		# Sanitise, discard newline and everything that follows
		value="${value%%$'\n'*}"

		# Assign a boolean type value
		case "$value" in
		[Nn][Oo] | [Ff][Aa][Ll][Ss][Ee] | '')
			$flags.[ "$var" ]= 0
			continue
		;;
		[Yy][Ee][Ss] | [Tt][Rr][Uu][Ee])
			$flags.[ "$var" ]= 1
			continue
		;;
		esac
		# Assign unsigned integer value
		if bsda:obj:isUInt "$value"; then
			$flags.[ "$var" ]= $((value))
			continue
		fi

		# Ignore non-boolean non-integral values
	done
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
