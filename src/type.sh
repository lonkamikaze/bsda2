test -n "$_type_" && return 0
readonly _type_=1

#
# Simple type checking and casting standalone library.
#
# @file
# @see type.md
#

#
# The given value matches at least one of the given types.
#
# @param 1
#	A comma separated list of types
# @param 2
#	The value to match
# @retval 0
#	At least one of the given types matches
# @retval 1
#	None of the given types fit the given value
#
type:match() {
	# Last type to check, terminate recursion
	if [ "${1#*,}" = "$1" ]; then
		type:match:$1 "$2"
		return $?
	fi

	# Recursively look for matching type
	type:match:${1%%,*} "$2" || type:match "${1#*,}" "$2"
}

#
# Cast to integer from a set of types.
#
# @param &1
#	The destination variable, only assigned in case of success
# @param 2
#	A comma separated list of matchable types
# @param 3
#	The value to assign
# @retval 0
#	Value successfully assigned
# @retval 1
#	None of the given types fit the given value
#
type:cast[int]() {
	# Last type to check, terminate recursion
	if [ "${2#*,}" = "$2" ]; then
		type:cast[int]:$2 "$1" "$3"
		return $?
	fi

	# Recursively look for matching type
	type:cast[int]:${2%%,*} "$1" "$3" || type:cast[int] "$1" "${2#*,}" "$3"
}

#
# Accept empty inputs.
#
# @param 1
#	The input string
# @return
#	Whether the input string is empty
#
type:match:empty() {
	test -z "$1"
}

#
# Accept boolean values.
#
# Accepts 0, 1, yes, no, true, false.
#
# @param 1
#	The input string
# @return
#	Whether the input string is a boolean value
#
type:match:bool() {
	case "$1" in
	0|1|[Yy][Ee][Ss]|[Nn][Oo]|[Tt][Rr][Uu][Ee]|[Ff][Aa][Ll][Ss][Ee])
		return 0
	;;
	esac
	return 1
}

#
# Accept unsigned integer values.
#
# Accepts hex, decimal and octal integer values without a sign.
#
# @param 1
#	The input string
# @return
#	Whether the input string is an unsigned integer
#
type:match:uint() {
	case "$1" in
	0[Xx]*)
		type:match:uint:base16 "${1#??}"
		return $?
	;;
	[1-9]*)
		type:match:uint:base10 "$1"
		return $?
	;;
	0*)
		type:match:uint:base8 "$1"
		return $?
	;;
	esac
	return 1
}

#
# Accept a string of hex digits.
#
# @param 1
#	The input string
# @return
#	Whether the input string consists of hex digits
#
type:match:uint:base16() {
	case "$1" in
	[0-9A-Fa-f])
		return 0
	;;
	[0-9A-Fa-f]*)
		type:match:uint:base16 "${1#?}"
		return $?
	;;
	esac
	return 1
}

#
# Accept a string of decimal digits.
#
# @param 1
#	The input string
# @return
#	Whether the input string consists of decimal digits
#
type:match:uint:base10() {
	case "$1" in
	[0-9])
		return 0
	;;
	[0-9]*)
		type:match:uint:base10 "${1#?}"
		return $?
	;;
	esac
	return 1
}

#
# Accept a string of octal digits.
#
# @param 1
#	The input string
# @return
#	Whether the input string consists of octal digits
#
type:match:uint:base8() {
	case "$1" in
	[0-7])
		return 0
	;;
	[0-7]*)
		type:match:uint:base8 "${1#?}"
		return $?
	;;
	esac
	return 1
}

#
# Accept integer values.
#
# Accepts hex, decimal and octal integer values with an optional sign.
#
# @param 1
#	The input string
# @return
#	Whether the input string is an integer
#
type:match:int() {
	type:match:uint "${1#[-+]}"
}

#
# Assign 0 on empty input.
#
# @param &1
#	The variable to assign to
# @param 2
#	The input string
# @return
#	Whether the input string is empty
#
type:cast[int]:empty() {
	if [ -z "$2" ]; then
		eval "$1=0"
		return 0
	fi
	return 1
}

#
# Assign 0 or 1 on boolean input.
#
# Accepts 0, 1, yes, no, true, false.
#
# @param &1
#	The variable to assign to
# @param 2
#	The input string
# @return
#	Whether the input string is a boolean value
#
type:cast[int]:bool() {
	case "$2" in
	0|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee])
		eval "$1=0"
		return 0
	;;
	1|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee])
		eval "$1=1"
		return 0
	;;
	esac
	return 1
}

#
# Assign unsigned decimal integer on unsigned integer input.
#
# Accepts hex, decimal and octal integer values without a sign.
#
# @param &1
#	The variable to assign to
# @param 2
#	The input string
# @return
#	Whether the input string is an unsigned integer
#
type:cast[int]:uint() {
	if type:match:uint "$2"; then
		eval "$1=\$(($2))"
		return 0
	fi
	return 1
}

#
# Assign decimal integer on integer input.
#
# Accepts hex, decimal and octal integer values with an optional sign.
#
# @param &1
#	The variable to assign to
# @param 2
#	The input string
# @return
#	Whether the input string is an integer
#
type:cast[int]:int() {
	if type:match:int "$2"; then
		eval "$1=\$(($2))"
		return 0
	fi
	return 1
}
