. ${bsda_dir:-.}/bsda_err.sh
. ${bsda_dir:-.}/type.sh

#
# Provides string formatting with named arguments.
#
# Formatting is provided by the bsda:fmt() function, which returns
# the formatted string to the variable named by the first argument.
# The bsda:fmt:printf() function prints the formatted string to stdout,
# it is equivalent to calling bsda:fmt() with the first argument
# left empty.
#
# The formatting string follows the same structure as a printf(1)
# formatting string, supporting the same escapes etc.. In fact the
# actual formatting work is performed by printf. The difference is
# that the '%' character has no effect, instead formatting fields
# are enclosed by braces: `{name}`
# The values are provided as additional arguments: `name=value`
# The order of arguments does not have to match the order of substituted
# fields.
#
# Substitution fields with only a name are formatted like '%s' by
# printf. Printf style formatting can be applied by following the
# substitution name with a colon and a printf formatting.
# E.g. `{name:04d}` is formatted like `%04d` by printf. The padding
# and spacing rules can be given without the type character, in
# that case 's' is implied.
#
# A special twist is that arithmetic expressions are allowed within
# the formatting section of a substitution field. An arithmetic
# expression must be enclosed by parenthesis.
# E.g. `{str:(width)}` pads the `str` argument to the size given
# by the `width` argument.
#
# @file
#

#
# Error/exit codes for error reporting.
#
# | Code                   | Severity | Meaning                             |
# |------------------------|----------|-------------------------------------|
# | E_BSDA_FMT_SUB         | error    | Substitution argument missing       |
# | E_BSDA_FMT_SUB_ID      | error    | Illegal substitution identifier     |
# | E_BSDA_FMT_SUB_FORMAT  | error    | Illegal substitution format         |
# | E_BSDA_FMT_EXPR        | error    | Illegal arithmetic expression       |
# | E_BSDA_FMT_EXPR_ASSIGN | error    | Assignment in arithmetic expression |
# | E_BSDA_FMT_ARG         | error    | Illegal argument                    |
# | E_BSDA_FMT_TYPE        | error    | Wrong data type in field            |
#
bsda:err:createECs \
	E_BSDA_FMT_SUB \
	E_BSDA_FMT_SUB_ID \
	E_BSDA_FMT_SUB_FORMAT \
	E_BSDA_FMT_EXPR \
	E_BSDA_FMT_EXPR_ASSIGN \
	E_BSDA_FMT_ARG \
	E_BSDA_FMT_TYPE \

#
# Produce a formatted string.
#
# @param 1
#	The destination variable name, output is printed to stdout
#	if not given
# @param 2
#	The formatting string
# @param @
#	The substitution arguments `name=value`
# @retval 0
#	A string was produced
# @retval 1
#	An error was raised
# @throws E_BSDA_FMT_SUB
#	A substitution could not be matched with a substitution argument
# @throws E_BSDA_FMT_SUB_ID
#	Illegal substitution identifier
# @throws E_BSDA_FMT_SUB_FORMAT
#	Illegal character in substitution format
# @throws E_BSDA_FMT_EXPR
#	Illegal character in arithmetic expression
# @throws E_BSDA_FMT_EXPR_ASSIGN
#	Assignment in expression
# @throws E_BSDA_FMT_ARG
#	Illegal character in substitution argument
# @throws E_BSDA_FMT_TYPE
#	A field used in an arithmetic expression is not assigned an integer
#
bsda:fmt() {
	local _bsda_fmt_dst _bsda_fmt_res
	_bsda_fmt_dst="${1}"
	shift
	bsda:fmt:run "$@" || return $?
	if [ -n "${_bsda_fmt_dst}" ]; then
		eval "${_bsda_fmt_dst}=\"\${_bsda_fmt_res}\""
	fi
}

#
# Print a formatted string on stdout.
#
# @param 1
#	The formatting string
# @param @
#	The substitution arguments `name=value`
# @retval 0
#	Printing the formatted string succeeded
# @retval 1
#	An error was raised
# @throws E_BSDA_FMT_SUB
#	A substitution could not be matched with a substitution argument
# @throws E_BSDA_FMT_SUB_ID
#	Illegal substitution identifier
# @throws E_BSDA_FMT_SUB_FORMAT
#	Illegal character in substitution format
# @throws E_BSDA_FMT_EXPR
#	Illegal character in arithmetic expression
# @throws E_BSDA_FMT_EXPR_ASSIGN
#	Assignment in expression
# @throws E_BSDA_FMT_ARG
#	Illegal character in substitution argument
# @throws E_BSDA_FMT_TYPE
#	A field used in an arithmetic expression is not assigned an integer
#
bsda:fmt:printf() {
	local _bsda_fmt_dst _bsda_fmt_res
	_bsda_fmt_dst=
	bsda:fmt:run "$@"
}

#
# Produce a formatted string.
#
# @param 1
#	The formatting string
# @param @
#	The substitution arguments `name=value`
# @param &_bsda_fmt_dst
#	Triggers return to variable
# @param &_bsda_fmt_res
#	Contains the resulting string if _bsda_fmt_dst is set, otherwise
#	the output is printed on stdout
# @retval 0
#	A string was produced
# @retval 1
#	An error was raised
# @throws E_BSDA_FMT_SUB
#	A substitution could not be matched with a substitution argument
# @throws E_BSDA_FMT_SUB_ID
#	Illegal substitution identifier
# @throws E_BSDA_FMT_SUB_FORMAT
#	Illegal character in substitution format
# @throws E_BSDA_FMT_EXPR
#	Illegal character in arithmetic expression
# @throws E_BSDA_FMT_EXPR_ASSIGN
#	Assignment in expression
# @throws E_BSDA_FMT_ARG
#	Illegal character in substitution argument
# @throws E_BSDA_FMT_TYPE
#	A field used in an arithmetic expression is not assigned an integer
#
bsda:fmt:run() {
	local IFS _fmt _arg _val _args _vars
	IFS=$'\n'

	# run the format generator, populates _fmt, _args and _vars
	bsda:fmt:gen "${1}"  || return $?
	shift

	# create locals from substitution arguments
	for _arg in "${@}"; do
		# only permit variables named /[a-z][a-z0-9_]*/i
		bsda:fmt:isarg "${_arg}" || return $?
		local "${_arg%%=*}"
		eval "${_arg%%=*}=\"\${_arg#*=}\""
	done
	# are requested substitutions provided by the argument list?
	for _arg in ${_args}; do
		if ! bsda:fmt:in "${_arg}" "$@"; then
			bsda:err:raise E_BSDA_FMT_SUB \
			               "ERROR: Substitution not in argument list: ${_arg}"
			return 1
		fi
	done
	# are requested variables provided by the argument list?
	for _arg in ${_vars}; do
		if ! bsda:fmt:in "${_arg}" "$@"; then
			bsda:err:raise E_BSDA_FMT_SUB \
			               "ERROR: Variable is not in argument list: ${_arg}"
			return 1
		fi
		eval "_val=\"\${${_arg}}\""
		if ! type:match:int "${_val}"; then
			bsda:err:raise E_BSDA_FMT_TYPE \
			               "ERROR: Variable used in arithmetic expression is not an integer: ${_arg}='${_val}'"
			return 1
		fi
	done

	# assemble printf arguments
	_vars=
	for _arg in ${_args}; do
		_vars="${_vars} \"\${${_arg}}\""
	done

	# print or assign
	if [ -n "${_bsda_fmt_dst:+defined}" ]; then
		_bsda_fmt_res="$(eval "printf ${_fmt}${_vars}" 2> /dev/null)"
	else
		eval "printf ${_fmt}${_vars}" 2> /dev/null
	fi
	return 0
}

#
# Determine if a substitution is in the list of substitution assignment
# arguments.
#
# @param 1
#	The needle, name of a substitution
# @param @
#	The haystack, a set of assignments `name=value`
# @retval 0
#	An assignment matches the requested substitution
# @retval 1
#	No assignment for the requested substitution is available
#
bsda:fmt:in() {
	local arg
	for arg in "${@}"; do
		case "${arg}" in
		"${1}="*) return 0;;
		esac
	done
	return 1
}

#
# Verify the given argument has the format /[a-z][a-z0-9_]*=.*/i.
#
# @param 1
#	The substitution argument to verify
# @retval 0
#	The argument is valid
# @retval 1
#	The argument is not a valid assignment
# @throws E_BSDA_FMT_ARG
#	For non-conforming arguments or assignment to IFS
#
bsda:fmt:isarg() {
	case "${1}" in
	IFS=*)
		bsda:err:raise E_BSDA_FMT_ARG \
		               "ERROR: Forbidden argument name: ${1%%=*}"
		return 1
	;;
	[a-zA-Z]*=*)
		if ! bsda:fmt:isarg:tail "${1#?}"; then
			bsda:err:raise E_BSDA_FMT_ARG \
			               "ERROR: Forbidden character in argument name: ${1%%=*}"
			return 1
		fi
	;;
	*=*)
		bsda:err:raise E_BSDA_FMT_ARG \
		               "ERROR: Forbidden first character in argument name: ${1%%=*}"
		return 1
	;;
	*)
		bsda:err:raise E_BSDA_FMT_ARG \
		               "ERROR: Not an argument assignment: ${1%%=*}"
		return 1
	;;
	esac
}

#
# Verify the given argument has the format /[a-z0-9_]*=.*/i.
#
# @param 1
#	The substitution argument to verify
# @retval 0
#	The argument is valid
# @retval 1
#	The argument is not a valid assignment
#
bsda:fmt:isarg:tail() {
	case "${1}" in
	[a-zA-Z0-9_]*)
	    bsda:fmt:isarg:tail "${1#?}";;
	=*) return 0;;
	*)  return 1;;
	esac
}

#
# Formatting string parser and generator.
#
# @param 1
#	The formatting string
# @param &_fmt
#	A double quoted string suitable for `eval "printf ${_fmt}"`
# @param &_args
#	A newline separated list of substitution fields that need
#	to be provided to the printf command as arguments in the
#	given order
# @param &_vars
#	A list of variables that need to be present for arithmetic
#	expressions within the formatting string
# @retval 0
#	The formatting string was successfully generated
# @retval 1
#	An error was raised
# @throws E_BSDA_FMT_SUB_ID
#	Illegal substitution identifier
# @throws E_BSDA_FMT_SUB_FORMAT
#	Illegal character in substitution format
# @throws E_BSDA_FMT_EXPR
#	Illegal character in arithmetic expression
# @throws E_BSDA_FMT_EXPR_ASSIGN
#	Assignment in expression
#
bsda:fmt:gen() {
	local f a v
	bsda:fmt:root "$(bsda:fmt:sanitise "${1}")" || return $?
	_fmt="\"${f}\""
	_args="${a}"
	_vars="${v}"
}

#
# Make the user provided string double-quote safe.
#
# - Protect `\{` and `\}` from the parser
# - Escape characters with special treatment within double quoted strings:
#   '$', '`', '"' and '\'
# - Double `%` characters for printf
#
bsda:fmt:sanitise() {
	case "${1}" in
	'\{'*)       echo -n '\173';             bsda:fmt:sanitise "${1#??}";;
	'\}'*)       echo -n '\175';             bsda:fmt:sanitise "${1#??}";;
	[\$\`\"\\]*) echo -n "\\${1%%"${1#?}"}"; bsda:fmt:sanitise "${1#?}";;
	%*)          echo -n '%%';               bsda:fmt:sanitise "${1#?}";;
	?*)          echo -n "${1%%"${1#?}"}";   bsda:fmt:sanitise "${1#?}";;
	esac
}

#
# Recursively reproduce the given string until a substitution is
# encountered.
#
# @param 1
#	The formatting string
# @param &f
#	All the characters up to the first substitution are appended
# @see bsda:fmt:sub()
#	Parse substitution expressions
#
bsda:fmt:root() {
	case "${1}" in
	\{*\}*) bsda:fmt:sub "${1#?}";;
	?*)     f="${f}${1%%"${1#?}"}"; bsda:fmt:root "${1#?}";;
	esac
}

#
# Allow /[a-z]/i as the first character in a substitution.
#
# @param 1
#	The formatting string starting at the first character inside
#	a substitution expression
# @param &a
#	First substitution ID character is appended
# @throws E_BSDA_FMT_SUB_ID
#	Illegal first character in substitution identifier
#
bsda:fmt:sub() {
	case "${1}" in
	[a-zA-Z]*)
	     a="${a}${1%%"${1#?}"}"; bsda:fmt:sub:id "${1#?}";;
	*)   bsda:err:raise E_BSDA_FMT_SUB_ID \
	                    "ERROR: Forbidden first character in substitution identifier: ${1}"
	     return 1;;
	esac
}

#
# Recursively allow /[a-z0-9_]/i characters in substitution IDs.
#
# @param 1
#	The formatting string starting behind the first character
#	of a substitution ID
# @param &a
#	The characters of the substitution ID and a newline are appended
# @param &f
#	- A `%s` formatting field is appended if the substitution ends
#	- A `%` is appended if a formatting section is encountered
# @see bsda:fmt:sub:format()
#	Parse formatting field if a `:` is encountered
# @see bsda:fmt:root()
#	Branch out of the substitution context
# @throws E_BSDA_FMT_SUB_ID
#	Illegal character in substitution identifier
#
bsda:fmt:sub:id() {
	case "${1}" in
	[a-zA-Z0-9_]*)
	     a="${a}${1%%"${1#?}"}"; bsda:fmt:sub:id "${1#?}";;
	:*)  a="${a}"$'\n'; f="${f}%";   bsda:fmt:sub:format "${1#?}";;
	\}*) a="${a}"$'\n'; f="${f}%s";  bsda:fmt:root "${1#?}";;
	*)   bsda:err:raise E_BSDA_FMT_SUB_ID \
	                    "ERROR: Forbidden character in substitution identifier: ${1}"
	     return 1;;
	esac
}

#
# Recursively allow /[-+# 0-9.]*[diouXxfFeEgGaAcsb]?/ in a format section.
#
# This is what is allowed with a printf formatting field. If the type
# character is missing, `s` for string formatting is assumed.
#
# @param 1
#	The formatting string set in the formatting section of a
#	substitution
# @param &f
#	- The formatting field is appended
#	- The character `s` is appended if the type character is missing
#	- The characters `$((` are appended if an arithmetic expression
#	  opened by a `(` character is encountered
# @see bsda:fmt:root()
#	Branch back at the end of the formatting field
# @see bsda:fmt:expr()
#	Parse an arithmetic expression opened with a `(` character
# @throws E_BSDA_FMT_SUB_FORMAT
#	A forbidden character was encountered
#
bsda:fmt:sub:format() {
	case "${1}" in
	[-+#\ 0-9.]*)
	     f="${f}${1%%"${1#?}"}"; bsda:fmt:sub:format "${1#?}";;
	[diouXxfFeEgGaAcsb]\}*)
	     f="${f}${1%%"${1#?}"}"; bsda:fmt:root "${1#??}";;
	\}*) f="${f}s";              bsda:fmt:root "${1#?}";;
	\(*) f="${f}\$((";           bsda:fmt:expr "${1#?}";;
	*)   bsda:err:raise E_BSDA_FMT_SUB_FORMAT \
	                    "ERROR: Forbidden character in format specification: ${1}"
	     return 1;;
	esac
}

#
# Pass arithmetic expressions without assignment operators.
#
# The beginning of an expression accepts unary operators, literals
# and variables.
# Variable names in expressions have to start with /[a-z]/i.
#
# @param 1
#	The formatting string starting inside an arithmetic expression
#	inside the formatting field of a substitution
# @param 2
#	The parenthesis depth, 0 assumed if not given
# @param &f
#	Append all unary operators up to the beginning of the first
#	literal, variable or subexpression
# @param &v
#	A newline separated list of encountered variable names is
#	appended
# @see bsda:fmt:expr:var()
#	To parse variable names inside the expression
# @see bsda:fmt:sub:format()
#	Branch back at the end of the expression
# @throws E_BSDA_FMT_EXPR
#	An illegal character was encountered
# @throws E_BSDA_FMT_EXPR_ASSIGN
#	Assignment in expression
#
bsda:fmt:expr() {
	case "${1}" in
	--*|++*|=*)
	     bsda:err:raise E_BSDA_FMT_EXPR_ASSIGN \
	                    "ERROR: Forbidden assignment in arithmetic expression: ${1}"
	     return 1;;
	[-!~+\ ]*)
	     # only unary operators at the beginning of an expression
	     f="${f}${1%%"${1#?}"}";   bsda:fmt:expr "${1#?}" ${2};;
	[a-zA-Z]*)
	     f="${f}${1%%"${1#?}"}";   v="${v}${1%%"${1#?}"}";
	     bsda:fmt:expr:var "${1#?}" ${2};;
	0[xX][0-9a-fA-F]*)
	     f="${f}${1%%"${1#???}"}"; bsda:fmt:expr:literal:hex "${1#???}" ${2};;
	0*)
	     f="${f}${1%%"${1#?}"}";   bsda:fmt:expr:literal:oct "${1#?}" ${2};;
	[1-9]*)
	     f="${f}${1%%"${1#?}"}";   bsda:fmt:expr:literal:dec "${1#?}" ${2};;
	\(*) f="${f}(";                bsda:fmt:expr "${1#?}" $((${2}+1));;
	*)   bsda:err:raise E_BSDA_FMT_EXPR \
	                    "ERROR: Forbidden character in arithmetic expression: ${1}" \
                            "       Expecting: '!', '~', '+', '-' or '('"
	     return 1;;
	esac
}

#
# Pass the tail of variable names within arithmetic expressions.
#
# The tail of a variable name is restricted to /[a-z0-9_]*/i.
#
# @param 1
#	The formatting string starting inside a variable name within
#	an arithmetic expression
# @param 2
#	The parenthesis depth
# @param &f
#	The variable name is appended
# @param &v
#	The variable name followed by a newline character is appended
# @see bsda:fmt:expr:operator()
#	Expect a binary/ternary operator or closing parenthesis after
#	a variable
#
bsda:fmt:expr:var() {
	case "${1}" in
	[a-zA-Z0-9_]*)
	     f="${f}${1%%"${1#?}"}"; v="${v}${1%%"${1#?}"}";
	     bsda:fmt:expr:var "${1#?}" ${2};;
	*)   v="${v}"$'\n'; bsda:fmt:expr:operator "${1}" ${2};;
	esac
}

#
# Pass the tail of a literal hexadecimal value /[0-9a-f]*/i.
#
# @param 1
#	The formatting string starting behind 0x?
# @param 2
#	The parenthesis depth
# @param &f
#	The integer literal is appended
# @see bsda:fmt:expr:operator()
#	Expect a binary/ternary operator or closing parenthesis after
#	a literal
#
bsda:fmt:expr:literal:hex() {
	case "${1}" in
	[0-9a-fA-F]*)
	     f="${f}${1%%"${1#?}"}"; bsda:fmt:expr:literal:hex "${1#?}" ${2};;
	*)   bsda:fmt:expr:operator "${1}" ${2};;
	esac
}

#
# Pass the tail of a literal octal value /[0-7]*/.
#
# @param 1
#	The formatting string starting behind 0
# @param 2
#	The parenthesis depth
# @param &f
#	The integer literal is appended
# @see bsda:fmt:expr:operator()
#	Expect a binary/ternary operator or closing parenthesis after
#	a literal
#
bsda:fmt:expr:literal:oct() {
	case "${1}" in
	[0-7]*) f="${f}${1%%"${1#?}"}"; bsda:fmt:expr:literal:oct "${1#?}" ${2};;
	*)      bsda:fmt:expr:operator "${1}" ${2};;
	esac
}

#
# Pass the tail of a literal decimal value /[0-9]*/.
#
# @param 1
#	The formatting string starting behind [1-9]
# @param 2
#	The parenthesis depth
# @param &f
#	The integer literal is appended
# @see bsda:fmt:expr:operator()
#	Expect a binary/ternary operator or closing parenthesis after
#	a literal
#
bsda:fmt:expr:literal:dec() {
	case "${1}" in
	[0-9]*) f="${f}${1%%"${1#?}"}"; bsda:fmt:expr:literal:dec "${1#?}" ${2};;
	*)      bsda:fmt:expr:operator "${1}" ${2};;
	esac
}

#
# Pass binary/ternary operators and closing parenthesis following
# a variable or integer literal.
#
# @param 1
#	The formatting string starting behind a variable or integer
# @param 2
#	The parenthesis depth
# @param &f
#	The operator or closing parenthesis is appended
# @throws E_BSDA_FMT_EXPR
#	An illegal character was encountered
# @throws E_BSDA_FMT_EXPR_ASSIGN
#	Assignment in expression
#
bsda:fmt:expr:operator() {
	case "${1}" in
	%%*) # fix the sanitiser doubling % characters
	     f="${f}%";               bsda:fmt:expr "${1#??}" ${2};;
	'<<'*|'>>'*|'<='*|'>='*|'=='*|'!='*|'&&'*|'||'*)
	     f="${f}${1%%"${1#??}"}"; bsda:fmt:expr "${1#??}" ${2};;
	--*|++*|=*)
	     bsda:err:raise E_BSDA_FMT_EXPR_ASSIGN \
	                    "ERROR: Forbidden assignment in arithmetic expression: ${1}"
	     return 1;;
	[-+*/\<\>\&\|\^?:]*)
	     f="${f}${1%%"${1#?}"}";  bsda:fmt:expr "${1#?}" ${2};;
	\ *)
	     f="${f}${1%%"${1#?}"}";  bsda:fmt:expr:operator "${1#?}" ${2};;
	\)*)
		if [ ${2:-0} -gt 0 ]; then
			f="${f})"
			bsda:fmt:expr:operator "${1#?}" $((${2}-1))
		else
			f="${f}))"
			bsda:fmt:sub:format "${1#?}"
		fi
	;;
	*)   bsda:err:raise E_BSDA_FMT_EXPR \
	                    "ERROR: Forbidden character in arithmetic expression: ${1}" \
                            "       Expecting: binary operator or ')'"
	     return 1;;
	esac
}
