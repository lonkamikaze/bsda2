test -n "$_bsda_test_" && return 0
readonly _bsda_test_=1

#
# Print failure and exit.
#
# @param 1
#	This should be $LINENO
# @param 2
#	The error number
#
bsda:test:err() {
	echo "Error $2 in line: $1"
	exit $2
}

#
# Check a string against a glob pattern.
#
# The glob pattern is passed through printf so special escapes like
# '\n' are supported. The '%' character must be duplicated.
#
# @param 1
#	The glob pattern to match
# @param 2
#	The string to check
# @retval 0
#	The string matches the pattern
# @retval 1
#	The string does not match the pattern
#
bsda:test:match() {
	case "$2" in
	$(printf "$1"))
		return 0
	;;
	esac
	return 1
}

#
# Return the function type of the given function.
#
# | Type       | Description                                       |
# |------------|---------------------------------------------------|
# | alias      | The given function is a shell alias               |
# | builtin    | The given function is a shell builtin             |
# | function   | The given function is a shell function            |
# | executable | The given function names a file system executable |
# | none       | The given function cannot be found                |
# | nil        | The `type` builtin returned an unsupported string |
#
# Note that `bash` only supports aliases in interactive mode.
#
# @param &1
#	The variable to receive the function type
# @param 2
#	The function to determine the type of
#
bsda:test:type() {
	setvar "$1" "$(
		case "$(type "$2" 2>&1 )" in
		"$2 is an alias "*|"$2 is aliased "*)
			echo alias
		;;
		"$2 is a shell builtin")
			echo builtin
		;;
		"$2 is a shell function"|"$2 is a function"*)
			echo function
		;;
		"$2 is /"*)
			echo executable
		;;
		*"$2: not found")
			echo none
		;;
		*)
			echo nil
		;;
		esac
	)"
}

#
# Check if the given function is an alias.
#
# @param 1
#	The name of the function
# @return
#	Returns 0 for yes and 1 for no
#
bsda:test:isAlias() {
	local type
	bsda:test:type type "$1"
	test "$type" = alias
}

#
# Check if the given function is a builtin.
#
# @param 1
#	The name of the function
# @return
#	Returns 0 for yes and 1 for no
#
bsda:test:isBuiltin() {
	local type
	bsda:test:type type "$1"
	test "$type" = builtin
}

#
# Check if the given function is a shell function.
#
# @param 1
#	The name of the function
# @return
#	Returns 0 for yes and 1 for no
#
bsda:test:isFunction() {
	local type
	bsda:test:type type "$1"
	test "$type" = function
}

#
# Check if the given function is a file system executable.
#
# @param 1
#	The name of the function
# @return
#	Returns 0 for yes and 1 for no
#
bsda:test:isExecutable() {
	local type
	bsda:test:type type "$1"
	test "$type" = executable
}

#
# Check if the given function cannot be found.
#
# @param 1
#	The name of the function
# @return
#	Returns 0 for yes and 1 for no
#
bsda:test:isNone() {
	local type
	bsda:test:type type "$1"
	test "$type" = none
}

#
# Check if the given variable exists.
#
# Note that this returns true for all defined variables, even empty
# ones.
#
# @param 1
#	The name of the variable
# @retval 0
#	The variable has been defined
# @retval 1
#	The variable does not exist
#
bsda:test:isSet() {
	eval "test -n \"\${$1+x}\""
}
