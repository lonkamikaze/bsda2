test -n "$_bsda_opts_" && return 0
readonly _bsda_opts_=1

. ${bsda_dir:-.}/bsda_container.sh
. ${bsda_dir:-.}/bsda_err.sh
. ${bsda_dir:-.}/type.sh

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
#	if $flags.check VERBOSE; then
#		echo "Starting in verbose mode" 1>&2
#	fi
#	if $flags.check VERBOSE -gt 1; then
#		echo "Be extra verbose" 1>&2
#	fi
#

#
# Error/exit codes for error reporting.
#
# | Code                | Severity | Meaning                                  |
# |---------------------|----------|------------------------------------------|
# | E_BSDA_OPTS_ENV     | warning  | Value of environment variable is invalid |
# | E_BSDA_OPTS_ASSIGN  | error    | Assigned value is invalid                |
# | E_BSDA_OPTS_DEFAULT | error    | Default value is invalid                 |
#
bsda:err:createECs \
	E_BSDA_OPTS_ENV=E_WARN \
	E_BSDA_OPTS_ASSIGN \
	E_BSDA_OPTS_DEFAULT

#
# Expression that splits the first chained short option argument.
#
# Use by calling `eval "$bsda_opts_split"` when bsda:opts:Options.getopt()
# returns OPT_SPLIT.
#
readonly bsda_opts_split='eval "$(bsda:opts:split "$@")"'

#
# Generates a `set --` command that splits the first argument with a
# single leading '-' into two arguments with a leading dash.
#
# This implements the functionality provided by bsda_opts_split.
#
# It exists because BASH and the ASH disagree on expanding `$@`.
# ASH applies substitutions applied to `$@` to the first argument
# only which enables this:
#
#	set -- "${1%"${1#-?}"}" "-${@#-?}"
#
# BASH applies the substitution to all expanded arguments, which is
# more intuitive but makes achieving this objective more complicated.
#
# @param 1
#	The argument to split
# @param @
#	The remaining arguments are reproduced unchanged
#
bsda:opts:split() {
	local i
	echo -n 'set -- "${1%"${1#-?}"}" "-${1#-?}"'
	i=1
	while [ $i -lt $# ]; do
		echo -n " \"\${$((i += 1))}\""
	done
}

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
	i:private:init   "The constructor" \
	x:public:add     "Count the given flag" \
	x:public:check   "Compare a flag numerically"

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
		# Sanitise, discard newline and everything that follows
		flag="${flag%%$'\n'*}"

		# Assign from argument
		case "$flag" in
		*\?=*)
			# Default assign
			if ! type:cast[int] value empty,bool,uint "${flag#*\?=}"; then
				bsda:err:raise E_BSDA_OPTS_DEFAULT \
				               "ERROR: Not a uint/bool assignment: ${flag}"
				continue
			fi
			var="${flag%%\?=*}"
			$flags.[ "$var" ]= "$value"
		;;
		*=*)
			# Assign
			if ! type:cast[int] value empty,bool,uint "${flag#*=}"; then
				bsda:err:raise E_BSDA_OPTS_ASSIGN \
				               "ERROR: Not a uint/bool assignment: ${flag}"
				continue
			fi
			var="${flag%%=*}"
			$flags.[ "$var" ]= "$value"
			# This assignment is complete
			continue
		;;
		*)
			# Just capture the name
			var="$flag"
		;;
		esac

		# Assign from environment
		if value="$(/usr/bin/printenv "$var")"; then
			if ! type:cast[int] value empty,bool,uint "$value"; then
				bsda:err:raise E_BSDA_OPTS_ENV \
				               "WARNING: Not a uint/bool assignment: env ${var}=${value}"
				continue
			fi
			$flags.[ "$var" ]= "$value"
		fi
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
	$flags.[ "$1" ]= $((value + 1))
}

#
# Perform numerical comparison with a flag.
#
# This method takes a flag, a test-style numerical operator (like
# -eq) and a numerical value.
#
# If the operator is omitted -ne 0 is implied.
#
# Uncounted flags compare -eq 0.
#
# @param 1
#	The flag to check the count of
# @param 2
#	The numerical comparison operator (optional)
# @param 3
#	The numerical value (optional)
# @retval 0
#	The comparison statement is true
# @retval 1
#	The comparison statement is false
#
bsda:opts:Flags.check() {
	local flags value
	$this.Flags flags
	$flags.[ "$1" ] value
	test $((value)) "${2--ne}" $((${3-0}))
}
