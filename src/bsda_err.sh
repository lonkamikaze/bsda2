test -n "$_bsda_err_" && return 0
readonly _bsda_err_=1

. ${bsda_dir:-.}/bsda_obj.sh
. ${bsda_dir:-.}/type.sh

#
# Error handling facilities.
#
# @file
# @see bsda_err.md
#

#
# The greatest error/exit code value defined so far.
#
bsda_err_ecMax=-1

#
# A comma separated list of the defined error/exit codes and aliases.
#
bsda_err_ecs=

#
# The number of colours supported by the terminal.
#
bsda_err_colours="$(/usr/bin/tput Co)"

#
# Define colour escape sequences.
#
if [ "${bsda_err_colours}" -ge 256 ]; then
	readonly bsda_err_co_module=$'\033[38;5;117m'    \
	         bsda_err_co_error=$'\033[1;38;5;124m'   \
	         bsda_err_co_warning=$'\033[1;38;5;215m' \
	         bsda_err_co_hint=$'\033[1;38;5;112m'    \
	         bsda_err_co_reset=$'\033[m'
elif [ "${bsda_err_colours}" -ge 16 ]; then
	readonly bsda_err_co_module=$'\033[38;5;4m'    \
	         bsda_err_co_error=$'\033[1;38;5;1m'   \
	         bsda_err_co_warning=$'\033[1;38;5;3m' \
	         bsda_err_co_hint=$'\033[1;38;5;2m'    \
	         bsda_err_co_reset=$'\033[m'
else
	readonly bsda_err_co_module=  \
	         bsda_err_co_error=   \
	         bsda_err_co_warning= \
	         bsda_err_co_hint=    \
	         bsda_err_co_reset=
fi

#
# Define error/exit codes.
#
# Takes a list of error/exit code names and aliases. Arguments may
# have the following form:
#
# - `<name>`
#   A symbolic error/exit code name is assigned a sequential number
# - `<alias name>=<name>`
#   An alias may reference a previously defined error/exit code
# - `<alias name>=<number>`
#   An alias may be assigned a fixed integral value
#
# The following error conditions exist:
#
# - Redefining a symbol or alias is a fatal error (exit code 2)
# - Assigning a non-integral value is a fatal error (exit code 2)
#
# @param @
#	A list of symbolic error/exit code names and aliases
# @param bsda_err_ecMax
#	The greatest assigned sequential number
# @param bsda_err_ecs
#	A comma separated record of error/exit code names/aliases
#
bsda:err:createECs() {
	local arg
	for arg in "$@"; do
		case "$arg" in
		*=*)
			# Create an alias
			if ! setvar ${arg%%=*} $((${arg#*=})); then
				module=bsda:err:createECs bsda:err:panic E_FAIL \
					"Cannot assign alias $arg!"
			fi
		;;
		*)
			# Create a new exit number
			if ! setvar $arg $((bsda_err_ecMax += 1)); then
				module=bsda:err:createECs bsda:err:panic E_FAIL \
					"Cannot assign $arg!"
			fi
		;;
		esac
		readonly ${arg%%=*}
		bsda_err_ecs="${bsda_err_ecs}${arg%%=*},"
	done
}

#
# Setup a basic set of error/exit codes.
#
bsda:err:createECs E_HINT=-1 E_WARN E_SIGNAL E_FAIL

#
# Provide the newline separated list of error/exit codes.
#
# Each code is given in the format `<name>=<number>`.
#
# @param &1
#	Reference to the destination variable, the list is output
#	on stdout if this is not provided
#
bsda:err:ecs() {
	if [ -n "$1" ]; then
		setvar "$1" "$(bsda:err:_ecs)"
	else
		bsda:err:_ecs
	fi
}

#
# Output a newline separated list of error/exit codes on stdout.
#
# This is a helper function for bsda:err:ecs().
#
bsda:err:_ecs() {
	local IFS ec
	IFS=,
	for ec in $bsda_err_ecs; do
		echo "${ec}=$((${ec}))"
	done
}

#
# The current error collecting context.
#
# Should point to a bsda:err:Context instance if set.
#
bsda_err_context=

#
# Print error or warning.
#
# @param 1
#	Print warning (yellow) for 0, hint (green) for negative integers
#	and an error (red) for positive integers
# @param *
#	Messages to print, each one on its own line
# @param module
#	Prefixed before the message, defaults to "${0##*/}"
# @param level
#	Prefixed before the message, defaults to "ERROR", "WARNING" or "HINT"
#	based parameter 1
#
bsda:err:print() (
	: ${module:="${0##*/}"}
	if [ $(($1)) -le $((E_HINT)) ]; then
		prefix="${module}: ${level:=HINT}:"
		cprefix="${bsda_err_co_module}${module}: ${bsda_err_co_hint}${level}:${bsda_err_co_reset}"
	elif [ $(($1)) -eq $((E_WARN)) ]; then
		prefix="${module}: ${level:=WARNING}:"
		cprefix="${bsda_err_co_module}${module}: ${bsda_err_co_warning}${level}:${bsda_err_co_reset}"
	else
		prefix="${module}: ${level:=ERROR}:"
		cprefix="${bsda_err_co_module}${module}: ${bsda_err_co_error}${level}:${bsda_err_co_reset}"
	fi
	if [ -n "$2" ]; then
		if [ -t 1 ]; then
			printf "${cprefix} %s\n" "$2"
		else
			printf "${prefix} %s\n" "$2"
		fi
		shift 2
		if [ -n "$1" ]; then
			indent="$(printf "%${#prefix}s" "")"
			printf "${indent} %s\n" "$@"
		fi
	fi
) >&2

#
# Check the given argument whether it is a valid error/exit code.
#
# @param 1
#	The value to check, either a variable name containing an
#	error/exit code, or an integral value
# @retval 0
#	The given error/exit code is valid
# @retval $E_FAIL
#	The given error/exit code is invalid
#
bsda:err:verify_errno() {
	if ! ( : $(($1)) ) 2>&-; then
		module=bsda:err bsda:err:print E_FAIL \
			"Not a valid exit code: <$1>"
		bsda_err_context=
		return ${E_FAIL}
	elif type:match:varname "$1" && eval "[ -z \"\${$1+1}\" ]"; then
		module=bsda:err bsda:err:print E_FAIL \
			"Undefined exit code: <$1>"
		return ${E_FAIL}
	fi
	return 0
}

#
# Prints a message on stderr and exits if the given code is non-zero.
#
# @param 1
#	An error/exit code
# @param @
#	An optional message printed on stderr, regardless of the error/exit code
# @param module
#	Prefixed before the message, defaults to "${0##*/}"
# @param level
#	Prefixed before the message, defaults to "ERROR", "WARNING" or "HINT"
#	based parameter 1
# @warning
#	Terminates the program if the error/exit code is non-zero
#
bsda:err:panic() {
	if ! bsda:err:verify_errno "$1"; then
		shift
		set -- E_FAIL "$@"
	fi
	bsda:err:print "$1" "$2" #"$@"
	if [ $(($1)) -gt 0 ]; then
		# flush pending errors
		if [ -n "${bsda_err_context}" ]; then
			local e msg module level
			while bsda:err:get e msg module level; do
				bsda:err:print "${e}" "${msg}"
			done
		fi
		exit $(($1))
	fi
}

#
# Create a new issue handling context.
#
# An issue handling context is a FIFO of issues created with
# bsda:err:raise(), retrieval is done with bsda:err:get().
#
bsda:err:collect() {
	bsda:err:Context bsda_err_context
	$caller.delete "$bsda_err_context"
}

#
# Raise an issue in the current issue handling context.
#
# Issues can be retrieved calling bsda:err:get().
#
# Defers to bsda:err:panic() if no context exists.
#
# @param 1
#	An error/exit code
# @param @
#	An error/warning message
# @param module
#	Prefixed before the message, defaults to "${0##*/}"
# @param level
#	Prefixed before the message, defaults to "ERROR", "WARNING" or "HINT"
#	based parameter 1
# @return
#	Returns the given error/exit code if it is a positive integer
# @warning
#	May terminate the program if the error/exit code is non-zero
#
bsda:err:raise() {
	if ! bsda:err:verify_errno "$1"; then
		shift
		set -- E_FAIL "$@"
		bsda:err:panic "$@"
	elif [ -z "$bsda_err_context" ]; then
		bsda:err:panic "$@"
	else
		$bsda_err_context.raise "$@"
	fi
	return $(($1 > 0 ? $1 : 0))
}

#
# Retrieve the next issue from the current context.
#
# @param &1
#	The destination variable for the error/exit code
# @param &2
#	The destination variable for the message
# @param &3
#	The destination variable for the module name
# @param &4
#	The destination variable for the escalation level
# @retval 0
#	An issue was successfully retrieved
# @retval 1
#	No issues remain in context
# @warning
#	Panics with E_FAIL if no context exists
#
bsda:err:get() {
	if [ -z "$bsda_err_context" ]; then
		module=bsda:err bsda:err:panic E_FAIL "Cannot bsda:err:get without bsda:err:collect!"
	fi
	$bsda_err_context.get "$@"
}

#
# Raise an issue in the parent issue handling context.
#
# This is intended to be used if bsda:err:get() returned an issue
# that cannot be handled in the current context.
#
# Defers to bsda:err:panic() if there is no current context or if
# there is no parent context.
#
# @param 1
#	An error/exit code
# @param @
#	An error/warning message
# @param module
#	Prefixed before the message, defaults to "${0##*/}"
# @param level
#	Prefixed before the message, defaults to "ERROR", "WARNING" or "HINT"
#	based parameter 1
# @warning
#	May terminate the program if the error/exit code is equal to
#	or less than 0
# @warning
#	Panics with E_FAIL if no context exists
#
bsda:err:forward() {
	if [ -z "$bsda_err_context" ]; then
		module=bsda:err bsda:err:panic E_FAIL "Cannot bsda:err:forward without bsda:err:collect!"
	fi
	local context
	$bsda_err_context.getPrevious context
	if [ -n "$context" ]; then
		$context.raise "$@"
	else
		bsda:err:panic "$@"
	fi
}

#
# Just forward all issues to the parental error context.
#
# This is useful to collect multiple errors in a context, before deferring
# to caller handling.
#
# If no parent context exists this panics on the first error, but all of
# them will be printed.
#
bsda:err:finalise() {
	local e msg module level
	while bsda:err:get e msg module level; do
		bsda:err:forward "$e" "$msg"
	done
}

#
# Instances represent an issue consisting of an error/exit code,
# message pair.
#
bsda:obj:createClass bsda:err:Issue \
	r:private:module "The module that raised the issue" \
	r:private:level  "The escalation level of the message" \
	r:private:e      "The error/exit code" \
	r:private:msg    "The error/warning message" \
	i:private:init   "Initialise the issue" \
	x:public:get     "Retrieve the error/exit code and message"

#
# Initialise the issue.
#
# @param 1
#	An error/exit code
# @param @
#	An error/warning message
# @param module
#	Prefixed before the message, defaults to "${0##*/}"
# @param level
#	Prefixed before the message, defaults to "ERROR", "WARNING" or "HINT"
#	based parameter 1
#
bsda:err:Issue.init() {
	local IFS=$'\n'
	setvar ${this}module "${module}"
	setvar ${this}level  "${level}"
	setvar ${this}e      "$1"
	shift
	setvar ${this}msg    "$*"
}

#
# Retrieve the error/exit code and error/warning message.
#
# @param &1
#	The destination variable for the error/exit code
# @param &2
#	The destination variable for the message
# @param &3
#	The destination variable for the module name
# @param &4
#	The destination variable for the escalation level
#
bsda:err:Issue.get() {
	local e msg mod lvl
	$this.getE      e
	$this.getMsg    msg
	$this.getModule mod
	$this.getLevel  lvl
	$caller.setvar "$1" "$e"
	$caller.setvar "$2" "$msg"
	$caller.setvar "$3" "$mod"
	$caller.setvar "$4" "$lvl"
}

#
# Instances represent an error handling context.
#
bsda:obj:createClass bsda:err:Context \
	r:public:previous "The previous (parent) context" \
	r:private:issues  "A list of active issues" \
	i:private:init    "Record the parent context" \
	c:private:clean   "Finalise this context" \
	x:public:raise    "Add an issue to the context" \
	x:public:get      "Pop an issue off the beginning of the list"

#
# Remember the parent context to restore when this context goes out
# of scope.
#
# @param bsda_err_context
#	Set to this context
#
bsda:err:Context.init() {
	setvar ${this}previous "$bsda_err_context"
	rec ${this}issues=
}

#
# Perform sanity checks, complain and recover as far as possible.
#
# - If this context is still active
#   - Restore parent context
#   - Print hints on processing issues
# - If issues remain in this context
#   - Attempt to forward them to the parent context
#     - Complain about deferring unhandled issues
#   - Otherwise print issue messages
#     - Complain about dropping unhandled issues
#
# @param bsda_err_context
#	Restore to previous context if this context is still active
#
bsda:err:Context.clean() {
	local previous
	if [ "$bsda_err_context" = $this ]; then
		module=bsda:err bsda:err:print E_HINT                     \
			"Use bsda:err:get to handle issues"               \
			"Use bsda:err:panic to terminate on an issue"     \
			"Use bsda:err:forward to defer handling an issue"
		$this.getPrevious bsda_err_context
	fi
	if rec ${this}issues.is_not_empty; then
		$this.getPrevious previous
		if [ -n "$previous" ]; then
			rec ${previous}issues.append ${this}issues
			module=bsda:err bsda:err:print E_WARN \
				"Unhandled issue(s) deferred to parent context!"
			return 0
		fi
		local e msg module level
		module=bsda:err bsda:err:print E_WARN \
			"Reached end of error context with unhandled issue(s)!" \
			"Dropping unhandled issue(s)!"
		while $this.get e msg module level; do
			bsda:err:print "${e}" "${msg}"
		done
	fi
	return 0
}

#
# Append an issue to the list of issues.
#
# @param 1
#	An error/exit code
# @param @
#	An error/warning message
# @param module
#	Prefixed before the message, defaults to "${0##*/}"
# @param level
#	Prefixed before the message, defaults to "ERROR", "WARNING" or "HINT"
#	based parameter 1
#
bsda:err:Context.raise() {
	local issue
	bsda:err:Issue issue "$@"
	rec ${this}issues.push_back "${issue}"
}

#
# Pop the first issue off the list of issues.
#
# @param &1
#	The destination variable for the error/exit code
# @param &2
#	The destination variable for the message
# @param &3
#	The destination variable for the module name
# @param &4
#	The destination variable for the escalation level
# @param bsda_err_context
#	Restored to the previous context if no issue is available
# @retval 0
#	An issue was retrieved
# @retval 1
#	No issues are available from the context
#
bsda:err:Context.get() {
	local issue e msg mod lvl
	if rec ${this}issues.pop_front issue; then
		$issue.get e msg mod lvl
		$caller.setvar "$1" "$e"
		$caller.setvar "$2" "$msg"
		$caller.setvar "$3" "$mod"
		$caller.setvar "$4" "$lvl"
		$issue.delete 1
		return 0
	fi
	$this.getPrevious bsda_err_context
	return 1
}
