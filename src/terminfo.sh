test -n "$_terminfo_" && return 0
readonly _terminfo_=1

#
# Provide terminal information and utility functions.
#
# @file
#

#
# The number of colours supported by the terminal.
#
readonly ti_colours="$(/usr/bin/tput Co 2>&-)"

#
# Define colour escape sequences.
#
if [ "${ti_colours}" -ge 256 ]; then
	readonly ti_fmt_module=$'\033[38;5;117m'    \
	         ti_fmt_error=$'\033[1;38;5;124m'   \
	         ti_fmt_warning=$'\033[1;38;5;215m' \
	         ti_fmt_hint=$'\033[1;38;5;112m'    \
	         ti_fmt_grey=$'\033[38;5;250m'      \
	         ti_fmt_status=$'\033[2m'           \
	         ti_fmt_reset=$'\033[m'
elif [ "${ti_colours}" -ge 16 ]; then
	readonly ti_fmt_module=$'\033[38;5;4m'    \
	         ti_fmt_error=$'\033[1;38;5;1m'   \
	         ti_fmt_warning=$'\033[1;38;5;3m' \
	         ti_fmt_hint=$'\033[1;38;5;2m'    \
	         ti_fmt_grey=$'\033[38;5;7m'      \
	         ti_fmt_status=$'\033[2m'         \
	         ti_fmt_reset=$'\033[m'
else
	readonly ti_fmt_module=  \
	         ti_fmt_error=   \
	         ti_fmt_warning= \
	         ti_fmt_hint=    \
	         ti_fmt_grey=    \
	         ti_fmt_status=  \
	         ti_fmt_reset=
fi

#
# Generate a set of string formatting functions.
#
# | Function         | Description                        |
# |------------------|------------------------------------|
# | ti:fmt:module()  | Emit the given text in blue        |
# | ti:fmt:error()   | Emit the given text in bold red    |
# | ti:fmt:warning() | Emit the given text in bold yellow |
# | ti:fmt:hint()    | Emit the given text in bold green  |
# | ti:fmt:grey()    | Emit the given text in grey        |
# | ti:fmt:status()  | Emit the given text dimmed         |
#
# The generated functions output the given text on stdout, wrapping
# it in terminal escape sequences to start the desired formatting
# and return to default formatting.
# The specific colours depend on whether the terminal supports
# 16 or >= 256 colours.
#
# If stderr is not connected to a terminal the text will be emitted
# on stdout without escape sequences.
#
# If no arguments are given, only the formatting escape sequence is
# emitted, the reset sequence can be emitted using ti:fmt:reset().
#
for _ti_fmt_sel in module error warning hint grey status; do
	eval "_ti_fmt=\"\${ti_fmt_${_ti_fmt_sel}}\""
	eval "ti:fmt:${_ti_fmt_sel}() {
		if [ -t 2 ]; then
			echo -n \"${_ti_fmt}\${1:+\"\${*}${ti_fmt_reset}\"}\"
		else
			echo -n \"\${*}\"
		fi
	}"
	unset _ti_fmt _ti_fmt_sel
done

#
# Emit the terminal formatting reset escape sequence if stderr is
# connected to a terminal.
#
ti:fmt:reset() {
	if [ -t 2 ]; then
		echo -n "${ti_fmt_reset}"
	fi
}
