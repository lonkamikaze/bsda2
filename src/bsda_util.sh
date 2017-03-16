test -n "$_bsda_util_" && return 0
readonly _bsda_util_=1

#
# A collection of utility functions.
#

#
# Splits a string and maps the fields to a list of variables.
#
# @param 1
#	The string to map
# @param 2
#	The separator
# @param &@
#	The variables to map fields of the string onto
#
bsda:util:map() {
	eval "shift 2
IFS='$2' read \"\$@\" << ba52378a-04a3-11e7-b355-0090f5f2f347
$1
ba52378a-04a3-11e7-b355-0090f5f2f347"
}

#
# Join all arguments.
#
# @param &1
#	The destination variable for the joined string
# @param 2
#	The separator character
# @param *
#	The arguments to join
#
bsda:util:join() {
	setvar "$1" "$(IFS="$2"; shift 2; echo "$*")"
}

#
# Split string by separator into space delimited list.
#
# @param &1
#	The source and destination variable
# @param 2
#	The separator character
#
bsda:util:split() {
	setvar "$1" "$(IFS="$2"; eval "echo \$$1")"
}

#
# Count the number of arguments.
#
# The destination variable is not counted.
#
# @param &1
#	The destination variable for the argument count
# @param @
#	The arguments to count
#
bsda:util:count() {
	setvar "$1" $(($# - 1))
}

#
# Test whether the first argument occurs in the following argument list.
#
# @param 1
#	The needle
# @param @
#	The haystack
# @retval 0
#	The needle is in the haystack
# @retval 1
#	No needle in the haystack
#
bsda:util:in() {
	local needle x
	needle="$1"
	shift
	for x in "$@"; do
		test "$x" = "$needle" && return 0
	done
	return 1
}
