test -n "$_compat_" && return 0
readonly _compat_=1

#
# Compatibility hacks.
#

# Emulate setvar for shells that don't have it, i.e. bash.
if ! setvar 2>&-; then
	setvar() {
		eval "${1:+$1="\$2"}"
	}
fi

# Setup getvar for symmetry with setvar
if ! getvar 2>&-; then
	#
	# Returns a variable from a given reference.
	#
	# The variable is either written to a named variable, or in
	# absence of one, output to stdout.
	#
	# @param &1
	#	The name of the variable to write to
	# @param 2
	#	The reference to the variable to return
	#
	getvar() {
		eval "${1:-echo \"\$$2\" #}=\"\${$2}\""
	}
fi
