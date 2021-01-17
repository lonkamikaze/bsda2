test -n "$_bsda_err_" && return 0
readonly _bsda_err_=1

. ${bsda_dir:-.}/bsda_obj.sh

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
				echo "bsda:err:createECs: ERROR: Cannot assign alias $arg!" >&2
				exit 2
			fi
		;;
		*)
			# Create a new exit number
			if ! setvar $arg $((bsda_err_ecMax += 1)); then
				echo "bsda:err:createECs: ERROR: Cannot assign $arg!" >&2
				exit 2
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
bsda:err:createECs E_OK E_WARN=E_OK E_SIGNAL E_FAIL

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
# Prints a message on stderr and exits if the given code is non-zero.
#
# @param 1
#	An error/exit code
# @param @
#	An optional message printed on stderr, regardless of the error/exit code
# @warning
#	Terminates the program if the error/exit code is non-zero
#
bsda:err:panic() {
	if [ -n "$2" ]; then
		(shift; IFS=$'\n'; echo "$*") >&2
	fi
	if ! ( : $(($1)) ) 2>&-; then
		echo "bsda:err:panic: Not a valid exit code: $1" >&2
		bsda_err_context=
		exit $((E_FAIL))
	fi
	if [ $(($1)) -ne 0 ]; then
		bsda_err_context=
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
# @warning
#	May terminate the program if the error/exit code is non-zero
#
bsda:err:raise() {
	if [ -z "$bsda_err_context" ]; then
		bsda:err:panic "$@"
	else
		$bsda_err_context.raise "$@"
	fi
}

#
# Retrieve the next issue from the current context.
#
# @param &1
#	The destination variable for the error/exit code
# @param &2
#	The destination variable for the message
# @retval 0
#	An issue was successfully retrieved
# @retval 1
#	No issues remain in context
# @warning
#	Panics with E_FAIL if no context exists
#
bsda:err:get() {
	if [ -z "$bsda_err_context" ]; then
		bsda:err:panic E_FAIL "bsda:err: ERROR: Cannot bsda:err:get without bsda:err:collect!"
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
# @warning
#	May terminate the program if the error/exit code is non-zero
# @warning
#	Panics with E_FAIL if no context exists
#
bsda:err:forward() {
	if [ -z "$bsda_err_context" ]; then
		bsda:err:panic E_FAIL "bsda:err: ERROR: Cannot bsda:err:forward without bsda:err:get!"
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
# Instances represent an issue consisting of an error/exit code,
# message pair.
#
bsda:obj:createClass bsda:err:Issue \
	r:private:e    "The error/exit code" \
	r:private:msg  "The error/warning message" \
	i:private:init "Initialise the issue" \
	x:public:get   "Retrieve the error/exit code and message"

#
# Initialise the issue.
#
# @param 1
#	An error/exit code
# @param @
#	An error/warning message
#
bsda:err:Issue.init() {
	local IFS=$'\n'
	setvar ${this}e  "$1"
	shift
	setvar ${this}msg "$*"
}

#
# Retrieve the error/exit code and error/warning message.
#
# @param &1
#	The destination variable for the error/exit code
# @param &2
#	The destination variable for the message
#
bsda:err:Issue.get() {
	local e msg
	$this.getE   e
	$this.getMsg msg
	$caller.setvar "$1" "$e"
	$caller.setvar "$2" "$msg"
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
	local issues previous prevIssues
	$this.getIssues issues
	$this.getPrevious previous
	if [ "$bsda_err_context" = $this ]; then
		echo "bsda:err: HINT: Use bsda:err:get to handle issues" >&2
		echo "bsda:err: HINT: Use bsda:err:panic to terminate on an issue" >&2
		echo "bsda:err: HINT: Use bsda:err:forward to defer handling an issue" >&2
		bsda_err_context="$previous"
	fi
	if [ -n "$issues" ]; then
		if [ -n "$previous" ] && $previous.getIssues prevIssues 2>&-; then
			setvar ${previous}issues "${prevIssues}${issues}"
			echo "bsda:err: WARNING: Unhandled issue(s) deferred to parent context!" >&2
			return 0
		fi
		local IFS issue e msg
		IFS=$'\n'
		for issue in $issues; do
			$issue.get e msg
			$issue.delete
			echo "$msg" >&2
		done
		echo "bsda:err: WARNING: Unhandled issue(s) dropped!" >&2
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
#
bsda:err:Context.raise() {
	local issues issue
	$this.getIssues issues
	bsda:err:Issue issue "$@"
	setvar ${this}issues "${issues}${issue}"$'\n'
}

#
# Pop the first issue off the list of issues.
#
# @param &1
#	The destination variable for the error/exit code
# @param &2
#	The destination variable for the message
# @param bsda_err_context
#	Restored to the previous context if no issue is available
# @retval 0
#	An issue was retrieved
# @retval 1
#	No issues are available from the context
#
bsda:err:Context.get() {
	local IFS issues issue e msg
	IFS=$'\n'
	$this.getIssues issues
	for issue in $issues; do
		$issue.get e msg
		$caller.setvar "$1" "$e"
		$caller.setvar "$2" "$msg"
		$issue.delete 1
		setvar ${this}issues "${issues#*${IFS}}"
		return 0
	done
	$this.getPrevious bsda_err_context
	return 1
}
