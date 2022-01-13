test -n "$_lst_sh_" && return 0
readonly _lst_sh_=1

#
# Portable string backed array library.
#
# @file
# @see lst.md
#

#
# Run lst() with RS set to the ASCII Line Feed character.
#
# @warning
#	The Line Feed character is White Space and thus subject to
#	special expansion rules, which affects the processing of
#	empty array entries with some methods.
# @param[in,out] @
#	Forwarded to lst()
#
log() { RS=$'\n'   lst "$@"; }

#
# Run lst() with RS set to the ASCII Record Separator character.
#
# @param[in,out] @
#	Forwarded to lst()
#
rec() { RS=$'\036' lst "$@"; }

#
# Run lst() with RS set to the ASCII comma `,` character.
#
# @param[in,out] @
#	Forwarded to lst()
#
csv() { RS=,       lst "$@"; }

#
# Interpret the first argument as the name of an array and an operator.
#
# @param[in,out] &1
#	The array to access and the operator to apply
# @param[in,out] @
#	Forwarded to the array methods
# @param[in] RS
#	The character separating array entries
#
lst() {
	case "$1" in
	*\[*\].*) eval "shift; lst:unpack '${1##*\].}' '${1%\].*}]' \"\${@}\"";;
	*\[*\]=)  eval "shift; lst:unpack set '${1%=}' \"\${@}\"";;
	*\[*\])   lst:unpack get "${@}";;
	*.*)      eval "shift; lst.${1#*.} '${1%%.*}' \"\$@\"";;
	*=cat)    eval "shift; lst:cat '${1%=cat}' \"\$@\"";;
	*=)       eval "$1; ${2+shift; lst.push_back '${1%=}' \"\$@\"}";;
	*)        lst.print "${@}";;
	esac
}

#
# Call an indexed array method using a packed array/index reference.
#
# The call `lst:unpack method array[index] ...` is unpacked into the
# call `lst.method_i array index ...`.
#
# @param[in] &1
#	The indexed function name
# @param[in,out] &2
#	Array name and index in the shape `name[index]`
# @param[in,out] @
#	Forwarded to lst.${1}_i
# @param[in] RS
#	The character separating array entries
#
lst:unpack() {
	eval "shift 2; set -- '${1}' '${2%\]}' \"\${@}\""
	eval "shift 2; lst.${1}_i '${2%%\[*}' '${2#*\[}' \"\$@\""
}

#
# Provide the indexed array entry.
#
# Items are indexed 1 to n (first to last) or -1 to -n (last to first).
#
# @warning
#	If RS is set to a White Space character empty entries are
#	invisible to the get_i() method. I.e. entries are indexed
#	as if the empty entries did not exist.
# @param[in] &1
#	Name of the array
# @param[in] 2
#	Index value or arithmetic expression (will be evaluated once)
# @param[out] &3
#	Optional destination variable name (print if unset)
# @param[in] RS
#	The character separating array entries
# @retval 0
#	Value is successfully returned/printed
# @retval 1
#	Out of bounds index
#
lst.get_i() {
	local IFS
	IFS="${RS}"
	eval "set -- \"\$((\${2}))\" \"\${3}\" \${$1}"
	eval "shift; set -- $(($1 > 0 ? $1 + 2 : $# + 1 + ($# + 1 + $1 >= 3 ? $1 : 0))) \"\${@}\""
	test $1 -le $# && eval "${2:-echo }${2:+=}\"\${$1}\""
}

#
# Assign the indexed array entry.
#
# Items are indexed 1 to n (first to last) or -1 to -n (last to first).
#
# @warning
#	If RS is set to a White Space character empty entries are
#	invisible to the set_i() method. I.e. entries are indexed
#	as if the empty entries did not exist and the resulting array
#	will contain no empty entries.
# @param[in,out] &1
#	Name of the array
# @param[in] 2
#	Index value or arithmetic expression (will be evaluated once)
# @param[in] 3
#	The value to assign
# @param[in] RS
#	The character separating array entries
# @retval 0
#	The entry was successfully updated
# @retval 1
#	Out of bounds index, the array remains unchanged
#
lst.set_i() {
	local IFS
	IFS="${RS}"
	eval "set -- \"\${1}\" \"\$((\${2}))\" \"\${3}\" \${$1}"
	eval "$(
	n=$(($2 > 0 ? $2 + 3 : $# + 1 + $2))
	if [ $n -le $# -a $n -gt 3 ]; then
		echo -n "$1=\""
		i=3
		while [ $((i += 1)) -le $# ]; do
			echo -n "\${$((i == n ? 3 : i))}\${RS}"
		done
		echo '"'
	else
		echo return 1
	fi
	)"
}

#
# Remove the indexed array entry.
#
# Items are indexed 1 to n (first to last) or -1 to -n (last to first).
#
# @warning
#	If RS is set to a White Space character empty entries are
#	invisible to the rm_i() method. I.e. entries are indexed
#	as if the empty entries did not exist and the resulting array
#	will contain no empty entries.
# @param[in,out] &1
#	Name of the array
# @param[in] 2
#	Index value or arithmetic expression (will be evaluated once)
# @param[in] RS
#	The character separating array entries
# @retval 0
#	The entry was successfully removed
# @retval 1
#	Out of bounds index, the array remains unchanged
#
lst.rm_i() {
	local IFS
	IFS="${RS}"
	eval "set -- \"\${1}\" \"\$((\${2}))\" \${$1}"
	eval "$(
	n=$(($2 > 0 ? $2 + 2 : $# + 1 + $2))
	if [ $n -le $# -a $n -gt 2 ]; then
		echo -n "$1=\""
		i=2
		while [ $((i += 1)) -le $# ]; do
			test $i -ne $n && echo -n "\${$i}\${RS}"
		done
		echo '"'
	else
		echo return 1
	fi
	)"
}

#
# Resize the array.
#
# If the given size is less than the current array size the tail of
# the array is cut off.
# If the given size is greater than the current array size, new entries
# are appended to the array. If the third argument does not provide
# a value, empty entries are appended.
#
# @warning
#	If RS is set to a White Space character empty entries are
#	invisible to the resize() method. I.e. empty entries disappear.
#	If the resulting array is shorter than the requested array size
#	new empty entries (or entries with the value of argument 3)
#	are appended to the array.
# @param[in,out] &1
#	Name of the array
# @param[in] 2
#	The new array size value or arithmetic expression (will be
#	evaluated once)
# @param[in] 3
#	Optionally provide a value used for new entries
#
lst.resize() {
	local IFS
	IFS="${RS}"
	eval "set -- \"\${1}\" \"\$((\${2}))\" \"\${3}\" \${$1}"
	eval "
	$1=\"$(
		n=$(($2 + 3))
		i=3
		while [ $((i += 1)) -le $n ]; do
			printf '${%s}${RS}' $((i <= $# ? i : 3))
		done
	)\"
	"
}

#
# Prepend values.
#
# @param[out] &1
#	Name of the array
# @param[in] @
#	Values to prepend
# @param[in] RS
#	The character separating array entries
#
lst.push_front() {
	eval "
	${2+$1=\"\${2\}\${RS\}\${$1\}\"}
	${3+shift 2; lst.push_front $1 \"\$@\"}
	"
}

#
# Append values.
#
# @param[out] &1
#	Name of the array
# @param[in] @
#	Values to append
# @param[in] RS
#	The character separating array entries
#
lst.push_back() {
	eval "
	${2+$1=\"\${$1\}\${2\}\${RS\}\"}
	${3+shift 2; lst.push_back $1 \"\$@\"}
	"
}

#
# Read first value.
#
# @param[in] &1
#	Name of the array
# @param[in] &2
#	Optional destination variable name (print if unset)
# @param[in] RS
#	The character separating array entries
# @retval 0
#	First entry returned successfully
# @retval 1
#	Array is empty
#
lst.peek_front() {
	eval "
	test -n \"\${$1}\" && \
	${2:-echo }${2:+=}\"\${$1%%\"\${RS}\"*}\"
	"
}

#
# Read last value.
#
# @param[in] &1
#	Name of the array
# @param[in] &2
#	Optional destination variable name (print if unset)
# @param[in] RS
#	The character separating array entries
# @retval 0
#	Last entry returned successfully
# @retval 1
#	Array is empty
#
lst.peek_back() {
	eval "
	test -n \"\${$1}\" && \
	set -- \"\${$1%\"\${RS}\"}\" && \
	${2:-echo }${2:+=}\"\${1##*\"\${RS}\"}\"
	"
}

#
# Pop first value.
#
# @param[in,out] &1
#	Name of the array
# @param[out] &2
#	Optional destination variable name (print if unset)
# @param[out] &@
#	Additional destinations are filled with popped values in sequence
# @param[in] RS
#	The character separating array entries
# @retval 0
#	All pop requests were completed successfully
# @retval > 0
#	The argument position of the first variable name that could
#	not be assigned, because the array is empty
#
lst.pop_front() {
	lst.peek_front "$@" && \
	eval "
	$1=\"\${$1#*\"\${RS}\"}\"
	${3+shift 2; lst.pop_front $1 \"\$@\" || return \$((\$? + 1))}
	"
}

#
# Pop last value.
#
# @param[in,out] &1
#	Name of the array
# @param[out] &2
#	Optional destination variable name (print if unset)
# @param[out] &@
#	Additional destinations are filled with popped values in sequence
# @param[in] RS
#	The character separating array entries
# @retval 0
#	All pop requests were completed successfully
# @retval > 0
#	The argument position of the first variable name that could
#	not be assigned, because the array is empty
#
lst.pop_back() {
	lst.peek_back "$@" && \
	eval "
	$1=\"\${$1%\"\${RS}\"}\"
	$1=\"\${$1%\"\${$1##*\"\${RS}\"}\"}\"
	${3+shift 2; lst.pop_back $1 \"\$@\" || return \$((\$? + 1))}
	"
}

#
# Remove the first entry matching the given value(s).
#
# @param[in,out] &1
#	Name of the array
# @param[in] 2
#	The value to remove
# @param[in] @
#	Additional values to remove
# @param[in] RS
#	The character separating array entries
# @retval 0
#	All values were matched and removed
# @retval > 0
#	The argument position of the first value that could not be
#	found in the array, subsequent argument values are not processed
#
lst.rm_first() {
	eval "
	case \"\${$1}\" in
	\"\${2}\${RS}\"*)
		$1=\"\${$1#\"\${2}\${RS}\"}\";;
	*\"\${RS}\${2}\${RS}\"*)
		$1=\"\${$1%%\"\${RS}\${2}\${RS}\"*}\${RS}\${$1#*\"\${RS}\${2}\${RS}\"}\";;
	*)
		return 1;;
	esac
	${3+shift 2 && lst.rm_first $1 \"\$@\" || return \$((\$? + 1))}
	"
}

#
# Remove the last entry matching the given values.
#
# @param[in,out] &1
#	Name of the array
# @param[in] 2
#	The value to remove
# @param[in] @
#	Additional values to remove
# @param[in] RS
#	The character separating array entries
# @retval 0
#	All values were matched and removed
# @retval > 0
#	The argument position of the first value that could not be
#	found in the array, subsequent argument values are not processed
#
lst.rm_last() {
	eval "
	case \"\${$1}\" in
	*\"\${RS}\${2}\${RS}\"*)
		$1=\"\${$1%\"\${RS}\${2}\${RS}\"*}\${RS}\${$1##*\"\${RS}\${2}\${RS}\"}\";;
	\"\${2}\${RS}\"*)
		$1=\"\${$1#\"\${2}\${RS}\"}\";;
	*)
		return 1;;
	esac
	${3+shift 2 && lst.rm_last $1 \"\$@\" || return \$((\$? + 1))}
	"
}

#
# Provide the number of array entries.
#
# @warning
#	If RS is set to a White Space character empty entries are
#	invisible to the count() method. I.e. this returns the number
#	of non-empty array entries.
# @param[in] &1
#	Name of the array
# @param[out] &2
#	Optional destination variable name (print if unset)
# @param[in] RS
#	The character separating array entries
#
lst.count() {
	local IFS
	IFS="${RS}"
	eval "
	set -- \${$1}
	${2:-echo }${2:+=}\$#
	"
}

#
# Check whether the given value is stored in the array.
#
# @param[in] &1
#	Name of the array
# @param[in] 2
#	The value to look for
# @param[in] RS
#	The character separating array entries
# @retval 0
#	The value is stored in the array
# @retval 1
#	The value is not stored in the array or no value given
#
lst.contains() {
	eval ${2+"
	case \"\${$1}\" in
	\"\${2}\${RS}\"* | *\"\${RS}\${2}\${RS}\"*) return 0;;
	*) return 1;;
	esac
	"} false
}

#
# Check whether all the given values are stored in the array.
#
# @param[in] &1
#	Name of the array
# @param[in] @
#	The values to look for
# @param[in] RS
#	The character separating array entries
# @retval 0
#	All values occur within the array
# @retval 1
#	One or more values do not occur within the array
#
lst.contains_all() {
	eval "${2+"lst.contains $1 \"\${2\}\" && shift 2 && lst.contains_all $1 \"\$@\""}"
}

#
# Check whether at least one of the given values is stored in the array.
#
# @param[in] &1
#	Name of the array
# @param[in] @
#	The values to look for
# @param[in] RS
#	The character separating array entries
# @retval 0
#	At least one value occurs within the array
# @retval 1
#	None of the given values occur within the array
#
lst.contains_any() {
	lst.contains "$@" || eval "shift 2 && lst.contains_any $1 \"\$@\""
}

#
# Print the array.
#
# @warning
#	If RS is set to a White Space character empty entries are
#	invisible to the print() method.
# @param[in] &1
#	Name of the array
# @param[in] &@
#	Optional names of additional arrays to print
# @param[in] RS
#	The character separating array entries
# @param[in] ORS
#	The first character is used as the Output Record Separator
#
lst.print() (
	IFS="${RS}" eval "set --$(printf ' ${%s}' "${@}")"
	IFS="${ORS}"
	echo "${*}"
)

#
# Print each array entry according to the given formatting string.
#
# @param[in] &1
#	Name of the array
# @param[in] 2
#	printf(1) formatting string, can use as many fields as array
#	items, repeats for additional items (so one field can be used
#	to print everything)
# @param[in] RS
#	The character separating array items
#
lst.printf() (
	IFS="${RS}"
	eval "printf \"\${2}\" \${$1}"
)

#
# Copy the record separator to the IRS variable.
#
# @param[in] RS
#	The character separating array items
# @param[out] IRS
#	The Input Record Separator
#
lst.set_irs() {
	IRS="${RS}"
}

#
# Copy the record separator to the ORS variable.
#
# @param[in] RS
#	The character separating array items
# @param[out] ORS
#	The Output Record Separator
#
lst.set_ors() {
	ORS="${RS}"
}

#
# Copy the record separator to the IFS variable.
#
# @param[in] RS
#	The character separating array items
# @param[out] IFS
#	The shell Input Field Separator
#
lst.set_ifs() {
	IFS="${RS}"
}

#
# Concatenate a set of arrays.
#
# All merged arrays must use the same RS character. Otherwise the
# resulting array is corrupted.
#
# @param[out] &1
#	The array to create/overwrite
# @param[in] &@
#	Names of the arrays to concatenate
# @param[in] RS
#	The character separating array entries
#
lst:cat() {
	eval "$1=\"$(shift; printf '${%s}' "${@}")\""
}

#
# Convert an array using one separator to another.
#
# E.g. use `IRS=$'\n' ORS=$'\036' lst:convert foo foo` to convert
# `foo` from an LF to an RS separated array.
#
# @warning
#	If IRS is set to a White Space character empty entries are
#	are lost during the conversion.
# @param[in] &1
#	Input array
# @param[out] &2
#	Optional output array (print on 1> if unset)
# @param[in] IRS
#	Input Record Separator
# @param[in] ORS
#	Output Record Separator
#
lst:convert() {
	eval "
	local IFS
	IFS=\"\${IRS}\"
	set -- \${$1} \${$1+''}
	IFS=\"\${ORS}\"
	${2:-echo }${2:+=}\"\${*}\"
	"
}

#
# Convert array type.
#
# E.g. use `lst:cast log:foo rec:foo` to convert `foo` from an LF
# to an RS separated array.
#
# @warning
#	If the input array RS is set to a White Space character empty
#	entries are lost during the conversion.
# @param[in] &1
#	Input array given as `type:array`
# @param[in,out] &2
#	Output array given as `type:array`, the array part is optional
#	(print on 1> if unset)
#
lst:cast() {
	local ORS IRS
	${1%:*} .set_irs
	${2%:*} .set_ors
	lst:convert ${1##*:} ${2##*:}
}
