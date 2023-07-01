test -n "$_bsda_util_" && return 0
readonly _bsda_util_=1

. ${bsda_dir:-.}/compat.sh

#
# A collection of utility functions.
#

#
# Splits a string and maps the fields to a list of variables.
#
# The string is split by applying sh(1) Field Splitting using the
# Input Field Separator. The values of unassigned fields are discarded.
#
# @param 1
#	The string to map
# @param &@
#	The variables to map fields of the string onto
# @param IFS
#	The separator
#
bsda:util:map() {
	eval "bsda:util:_map() {
		$(i=0; shift && for arg in "$@"; do
			echo "${arg}=\"\${$((i += 1))}\""
		done)
	}"
	bsda:util:_map $1
	unset -f bsda:util:_map
}

#
# Generates a field splitting function.
#
# The function assigns fields to the given set of variables. All
# arguments to the function are subjected to field splitting.
#
# The string is split by applying sh(1) Field Splitting using the
# Input Field Separator. The values of unassigned fields are discarded.
#
# This requires the vis(1) command to safely store the IFS value.
#
# @param 1
#	Name of the generated function
# @param &@
#	The variables to map fields of the string onto
# @param IFS
#	The separator
#
bsda:util:mapfun() {
	eval "$1() {
		local IFS
		IFS=\$'$(echo -n "${IFS}" | /usr/bin/vis -owe\')'
		set -- \$@
		$(i=0; shift && for arg in "$@"; do
			echo "		${arg}=\"\${$((i += 1))}\""
		done)
	}"
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
