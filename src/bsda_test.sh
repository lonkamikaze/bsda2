test -n "$_bsda_test_" && return 0
readonly _bsda_test_=1

#
# Print failure and exit.
#
# @param 1
#	This should be $LINENO
#
bsda:test:err() {
	echo "Failed in line: $1"
	exit 1
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
