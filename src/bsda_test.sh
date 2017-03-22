test -n "$_bsda_test_" && return 0
readonly _bsda_test_=1

#
# Print failure and exit.
#
# @param 1
#	The file name
# @param 2
#	This should be $LINENO
# @param 3
#	The error number
#
bsda:test:err() {
	echo "$1:$2: ERROR: $3" >&2
	exit $3
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
	case "$2." in
	$(printf "%b." "$1"))
		return 0
	;;
	esac
	return 1
}

#
# Each line is matched against a set of glob patterns.
#
# The return value depends on a relationship critereria that specifies
# how lines from the string should related to glob patterns:
#
# | Relationship | Description                                              |
# |--------------|----------------------------------------------------------|
# | all:any      | All lines match a pattern                                |
# | all:all      | All lines match a pattern, each pattern is matched       |
# | all:once     | All lines match a pattern, each pattern matches one line |
# | any:any      | At least one line matches a pattern                      |
# | any:all      | All patterns match at least one line                     |
# | any:once     | All patterns match one line                              |
#
# @param 1
#	The string to match against the patterns
# @param 2
#	The relationship between string lines and patterns
# @param @
#	The glob patterns to match against
# @retval 0
#	The relationship is satisfied
# @retval 1
#	The relationship is not satisfied
# @retval 13
#	The string line part of the relationship is unknown
# @retval 23
#	The pattern part of the relationship is unknown
#
bsda:test:xmatch() {
	local IFS rel str i
	IFS='
'
	str="$1"
	rel="$2"
	shift 2
	i=0
	while [ $i -lt $# ]; do
		local count_$i
		i=$((i + 1))
	done
	case "$rel" in
	all:any)
		for str in $str; do
			bsda:test:xmatch_any "$str" "$@" || return $?
		done
		return 0
	;;
	any:any)
		for str in $str; do
			bsda:test:xmatch_any "$str" "$@" && return 0
		done
		return 1
	;;
	all:*)
		for str in $str; do
			bsda:test:xmatch_count "$str" "$@" || return $?
		done
	;;
	any:*)
		for str in $str; do
			bsda:test:xmatch_count "$str" "$@"
		done
	;;
	*)
		# Unsupported relation
		return 13
	;;
	esac
	# Check counts
	case "$rel" in
	*:all)
		i=0
		while [ $i -lt $# ]; do
			# Bail out if a pattern was not matched
			if [ $((count_$i)) -eq 0 ]; then
				return 1
			fi
			i=$((i + 1))
		done
		return 0
	;;
	*:once)
		i=0
		while [ $i -lt $# ]; do
			# Bail out if a pattern was not matched once
			if [ $((count_$i)) -ne 1 ]; then
				return 1
			fi
			i=$((i + 1))
		done
		return 0
	;;
	esac
	# Unsupported relation
	return 23
}

#
# Helper function to bsda:test:xmatch().
#
# Checks the given line against the given patterns.
#
# @param 1
#	The string line to match against patterns
# @param @
#	The patterns to match against
# @retval 0
#	A pattern match was encountered
# @retval 1
#	None of the patterns are a match
#
bsda:test:xmatch_any() {
	local line pattern
	line="$1"
	pattern="$2"
	# Terminate recursion, when running out of patterns to mach
	if ! shift 2; then
		return 1
	fi
	# Try the current pattern
	case "$line" in
	$pattern)
		return 0
	;;
	esac
	# Try next pattern
	bsda:test:xmatch_any "$line" "$@"
}

#
# Helper function to bsda:test:xmatch().
#
# Counts the matches of each pattern.
#
# @param [count_0..count_$#)
#	Store the number of matches for each pattern
# @param 1
#	The string line to match against patterns
# @param @
#	The patterns to match against
# @retval 0
#	At least one pattern match was encountered
# @retval 1
#	None of the patterns are a match
#
bsda:test:xmatch_count() {
	local line pattern ret
	line="$1"
	pattern="$2"
	# Terminate recursion, when running out of patterns to mach
	if ! shift 2; then
		return 1
	fi
	# Recurse to next pattern
	bsda:test:xmatch_count "$line" "$@"
	ret=$?
	# Try the current pattern
	case "$line" in
	$pattern)
		: $((count_$# += 1))
		return 0
	;;
	esac
	return $ret
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
