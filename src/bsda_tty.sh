#
# Copyright (c) 2009, 2010, 2014, 2015
# Dominic Fandrey <kamikaze@bsdforen.de>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# Include once.
test -n "$_bsda_tty_" && return 0
readonly _bsda_tty_=1

# Include framework for object oriented shell scripting.
. ${bsda_dir:-.}/bsda_obj.sh

#
# A package for controlling the terminal and mixing status output on
# /dev/tty with regular output on /dev/stdout and /dev/stderr.
#
# Output duplication has been removed in favour of tee(1).
#
# Tested on:
#
# | Terminal     | TERM
# |--------------|--------
# | xterm        | xterm
# | console      | xterm
# | rxvt-unicode | rxvt
# | tmux         | screen
#

#
# A list of useful termcap(5) capabilities, used with tput(1):
#
# | Command            | Short    | Problems
# |--------------------|----------|-----------------------
# | save_cursor        | sc       |
# | restore_cursor     | rc       |
# | cursor_address     | cm #1 #2 |
# | cursor_home        | ho       |
# | columns            | co => #  |
# | lines              | li => #  |
# | clr_eol            | ce       |
# | clr_eos            | cd       |
# | delete_line        | dl       |
# | parm_insert_line   | AL #1    |
# | insert_line        | al       |
# | cursor_invisible   | vi       |
# | cursor_normal      | ve       |
# | cursor_visible     | vs       |
# | parm_down_cursor   | DO #1    | DO 0 glitches in tmux
# | parm_up_cursor     | UP #1    | UP 0 glitches in tmux
# | carriage_return    | cr       |
# | newline            | nw       |
# | cursor_down        | do       |
# | cursor_up          | up       |
# | eat_newline_glitch | xn       |
# | init_tabs          | it => #  |
#

# Terminal exceptions.
readonly bsda_tty_ERR_TERMINAL_STATUSPROVIDER_INVALID=1
readonly bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS=2
readonly bsda_tty_ERR_TERMINAL_STATUSPROVIDER_NOT_IN_LIST=3
readonly bsda_tty_ERR_TERMINAL_LINEINDEX_NOT_A_NUMBER=4
readonly bsda_tty_ERR_TERMINAL_LINECOUNT_NOT_UINT=5

#
# An error storage variable.
# If an error occurs this should be set back to 0 wherever the error is
# dealt with.
#
bsda_tty_errno=0

#
# A helper function library.
#
bsda:obj:createClass bsda:tty:Library \
	x:public:format             "A printf wrapper to format a line" \
	                            "adjusted to the terminal width" \
	x:public:convertBytes       "Provides byte count representations" \
	x:public:convertBytesToUnit "Provides byte count representations" \
	                            "with a fixed unit" \

#
# Convert byte counts into human readable values.
#
# This method runs out of units when peta bytes are reached.
#
# @param &1
#	The variable to return the converted byte in
# @param &2
#	The variable to return the the conversion unit in
# @param 3
#	The value to convert
# @param 4
#	The optional targeted maximum string length. A length below 3 leads
#	to 0 values between 1000 and 1024 of the underlying unit,
#	the default length is 4
#
bsda:tty:Library.convertBytes() {
	local width unit value scale decscale rest
	width=${4:-4}
	value="$(($3))"

	# Binary scaling factor as powers of 2.
	scale=0
	# Decimal scaling mutiplier.
	decscale=1
	for unit in ' ' k m g t p; do
		test ${#value} -le $width && break
		# Record scaling factors to calculate the rest.
		scale=$((scale + 10))
		decscale=$((decscale * 1000))
		# Convert the value to the next unit.
		value=$((value >> 10))
	done

	# Get the remainder out of the original value and scale it to a
	# decimal representation.
	rest=$((($3 - (value << scale)) * decscale / (1 << scale)))

	# Pad the value with digits.
	if [ $((${#value} + 1)) -lt $width ]; then
		value="$value."
		while [ ${#value} -lt $width ]; do
			value="$value${rest%%${rest#?}}"
			# Discard the first digit, fill from the right with 0.
			rest="${rest#?}0"
		done
	fi

	# Return results.
	$caller.setvar "$1" "$value"
	$caller.setvar "$2" "$unit"
}

#
# Convert byte counts into a specified representation.
#
# @param &1
#	The variable to return the converted byte in
# @param 2
#	The conversion unit either ' ', 'k', 'm', 'g', 't', 'p'
# @param 3
#	The value to convert
# @param 4
#	The optional targeted maximum string length. A length below 3 leads
#	to 0 values between 1000 and 1024 of the underlying unit,
#	the default length is 4
#
bsda:tty:Library.convertBytesToUnit() {
	local width targetUnit unit value scale decscale rest
	targetUnit="$2"
	width=${4:-4}
	value="$(($3))"

	# Binary scaling factor as powers of 2.
	scale=0
	# Decimal scaling mutiplier.
	decscale=1
	for unit in ' ' k m g t p; do
		test "$targetUnit" = "$unit" && break
		# Record scaling factors to calculate the rest.
		scale=$((scale + 10))
		decscale=$((decscale * 1000))
		# Convert the value to the next unit.
		value=$((value >> 10))
	done

	# Get the remainder out of the original value and scale it to a
	# decimal representation.
	rest=$((($3 - (value << scale)) * decscale / (1 << scale)))

	# Pad the value with digits.
	if [ $((${#value} + 1)) -lt $width ]; then
		value="$value."
		while [ ${#value} -lt $width ]; do
			value="$value${rest%%${rest#?}}"
			# Discard the first digit, fill from the right with 0.
			rest="${rest#?}0"
		done
	fi

	# Return results.
	$caller.setvar "$1" "$value"
}

#
# A printf wrapper that allows x-length columns that will stretch to use an
# entire terminal line. Overlong columns are forcibly shortened.
#
# The padding/shrinking of x-length columns is weighted according to the
# length of the corresponding arguments. To retain a consistent layout over
# several calls, only a single x-length column should be used.
#
# Under no circumstances will a line with more characters than available
# terminal columns be output. Should the terminal be unable to report the
# available columns, 80 is assumed.
#
# The following things break this function:
# - \r, \n, \t
#   - The formatting characters are all counted as 1 regular
#     character, so the output may end up too short or spreading
#     more than 1 line
# - unmatching number of arguments
#   - Providing the wrong number of arguments, causes them to show
#     up in the wrong output columns
#
# Format pattern insertions are defined in the following way:
#	PADDING :=	"0" | "-" | ""
#	WIDTH :=	[[:digit:]]* | "x" | ""
#	CUT :=		"-" | ""
#	STYLE :=	[[:alpha:]]
#	FORMAT :=	"<" PADDING WIDTH CUT ":" STYLE ">"
#
# | Definition | Pattern      | Description
# |------------|--------------|--------------------------------------
# | PADDING    | "0"          | The value is left-filled with "0"
# |            | "-"          | The value is right-padded
# |            | ""           | The value is left-padded
# | WIDTH      | [[:digit:]]* | A numeric value
# |            | "x"          | Auto-adjust
# |            | ""           | No adjustment
# | CUT	       | "-"          | Remove characters from the beginning
# |            | ""           | Remove trailing characters
# | STYLE      | [[:alpha:]]  | A character declaring a printf style
#
# @param &1
#	The return variable name
# @param 2
#	The pattern to convert and use
# @param @
#	The remaining arguments will be passed on to printf
#
bsda:tty:Library.format() {
	local IFS outvar pattern printf columns format arg width pad style
	local cutdirection output adjust xlen rest

	IFS='
'

	#TODO add support for all printf padding options
	outvar="$1"
	pattern="$2"
	shift 2
	columns=$(test -e /dev/tty && /usr/bin/tput co 2> /dev/tty || echo 80)
	/usr/bin/tput xn || columns=$((columns - 1))

	#
	# Normally the format pattern is parsed two times. The first time
	# hard coded column widths are enforced on the arguments. Afterwards
	# A render attempt is made, which provides the difference to the
	# desired output width.
	#

	# Working copy of the provided pattern.
	printf="$pattern"
	# Sum up the length of dynamically spaced arguments.
	xlen=0
	for format in $(echo "$pattern" | /usr/bin/egrep -o '<[0-]?([[:digit:]]*|x)-?:[[:alpha:]]>'); do
		# Get the formatting values
		style="${format##*:}";style="${style%>}"
		width="${format#<}";width="${width#[0-]}";width="${width%%:*}";width="${width%-}"
		pad="${format#<}";pad="${pad%%${pad#[0-]}}"
		cutdirection="${format%%:*}";cutdirection="${cutdirection#${cutdirection%-}}"

		# Get the argument, empty arguments are replaced with 0 or
		# space, depending on the padding setting.
		arg="${1:-${pad:+${pad#-}}}"
		arg="${arg:- }"
		shift

		if [ "$width" = "x" ]; then
			# Unset column with for the first rendering
			width=
			# Record argument length
			xlen=$((xlen + ${#arg}))
		elif [ -n "$width" -a "$width" -lt "${#arg}" ]; then
			# Limit to the width if one was specified.
			if [ -n "$cutdirection" ]; then
				# Cut from the left.
				arg="$(echo "$arg" | /usr/bin/sed -E "s,.*(.{$width})$,\1,")"
			else
				# Cut from the right.
				arg="$(printf "%.${width}s" "$arg")"
			fi
		fi 2> /dev/null

		# Preserve argument.
		set -- "$@" "$arg"
		printf="$(echo "$printf" | /usr/bin/sed -E "s,$format,%$pad$width$style,")"
	done
	output="$(printf "$printf" "$@")"

	#
	# The second pattern parsing is performed to adjust the width of
	# auto-adjusted colums. This can either mean cutting excess characters
	# away or to perform aditional padding.
	#
	# If no auto-adjusted columns exist or the first render attempt
	# yielded the correct width, the second pass is skipped and the first
	# pass prevails as the output.
	#

	#
	# Apply the appropriate padding/shrinking strategy.
	#

	# How many columns have to be added/removed?
	adjust=$((columns - ${#output}))
	if [ $xlen -eq 0 ]; then
		: # Nothing to stretch/shrink.
	elif [ $adjust -ne 0 ];  then
		# Pad/shrink arguments.
		printf="$pattern"
		for format in $(echo "$pattern" | /usr/bin/egrep -o '<[0-]?([[:digit:]]*|x)-?:[[:alpha:]]>'); do
			arg="$1"
			shift
			# Get the values
			style="${format##*:}";style="${style%>}"
			width="${format#<}";width="${width#[0-]}";width="${width%%:*}";width="${width%-}"
			pad="${format#<}";pad="${pad%%${pad#[0-]}}"
			cutdirection="${format%%:*}";cutdirection="${cutdirection#${cutdirection%-}}"
	
			if [ "$width" = "x" ]; then
				# Calculate new arg length.
				width=$((${#arg} + adjust * ${#arg} / xlen))
				rest=$((adjust * ${#arg} % xlen))
				if [ $rest -lt 0 ]; then
					width=$((width - 1))
					adjust=$((adjust + 1))
				elif [ $rest -gt 0 ]; then
					width=$((width + 1))
					adjust=$((adjust - 1))
				fi
				if [ $adjust -lt 0 ]; then
					# Remove from arg.
					if [ -n "$cutdirection" ]; then
						# Cut from the left.
						arg="$(echo "$arg" | /usr/bin/sed -E "s,.*(.{$width})$,\1,")"
					else
						# Cut from the right.
						arg="$(printf "%.${width}s" "$arg")"
					fi 2> /dev/null
				fi
			fi
	
			# Preserve argument.
			set -- "$@" "$arg"
			printf="$(echo "$printf" | /usr/bin/sed -E "s,$format,%$pad$width$style,")"
		done
	fi

	# Return the result.
	output="$(printf "%.${columns}s" "$(printf "$printf" "$@")")"
	$caller.setvar "$outvar" "$output"
}

#
# Instances of classes implementing this interface can be attached to status
# lines and will be queried for a new status line whenever the
# Terminal.refresh() method is called.
#
bsda:obj:createInterface bsda:tty:StatusProvider \
	x:reportStatus     "Returns a status line" \
	x:disconnectStatus "Is called if the status provider gets disconnected"

#
# Represents a terminal to control output on stdout, stderr and status lines.
#
# An instance can be deactivated, in which case status messages are discarded.
#
# For convenience it also inherits the methods of the helper function library.
#
bsda:obj:createClass bsda:tty:Terminal extends:bsda:tty:Library \
	w:private:active           "Terminal control active flag." \
	w:private:count            "The number of status lines" \
	w:private:visible          "The current visibility state" \
	w:private:providers        "A list of StatusProvider instances" \
	w:private:buffer           "A buffer of the status lines" \
	i:private:init             "The constructor checks whether a" \
	                           "terminal is available." \
	c:private:clean            "Notifies the StatusProvider instances" \
	x:private:draw             "Draws the buffer" \
	x:private:getDisplayCount  "Returns the number of status lines drawn" \
	x:private:getDisplayBuffer "Returns the portion of the buffer that" \
	                           "may be displayed." \
	x:public:deactivate        "Deactivates Terminal control" \
	x:public:use               "Controls the number of lines used for" \
	                           "status display" \
	x:public:hide              "Hide the status lines" \
	x:public:show              "Recover the last status display" \
	x:public:refresh           "Refresh status lines" \
	x:public:attach            "Attach a StatusProvider to a status line" \
	x:public:detach            "Detach a StatusProvider" \
	x:public:flush             "Detach all StatusProviders" \
	x:public:line              "Sets a status line" \
	x:public:stdout            "Write to stdout" \
	x:public:stderr            "Write to stderr"

#
# The constructor checks whether a terminal is available.
#
# In that case the object is configured to be active and have 0 status
# lines. Also the cursor display is deactivated.
#
bsda:tty:Terminal.init() {
	if [ -e /dev/tty ]; then
		$this.setActive 1
		$this.setCount 0
		$this.setVisible 1
	fi

	return 0
}

#
# The destructor removes the status lines, makes the cursor visible again
# and detaches all attached StatusProvider instances.
#
bsda:tty:Terminal.clean() {
	local active

	$this.getActive active
	if [ -n "$active" ]; then
		$this.hide
	fi

	$this.flush

	return 0
}

#
# Draw the buffer to stdout, make sure not to use more lines than the terminal
# currently provides.
#
# This method does not make sure that it is drawing to the terminal. Output
# has to be directed by the caller.
#
bsda:tty:Terminal.draw() {
	local buffer count

	$this.getDisplayBuffer buffer count
	/usr/bin/tput vi cr AL $count
	echo -n "$buffer"
	/usr/bin/tput cr UP $((count)) do ve
}

#
# Returns the number of status lines that may be output.
#
# This is either the number of available lines or half the terminal height,
# whichever one is shorter.
#
# @param &1
#	The number of lines to display.
#
bsda:tty:Terminal.getDisplayCount() {
	local count maxlines
	maxlines=$(($(/usr/bin/tput li 2> /dev/tty || echo 24) / 2))
	$this.getCount count
	if [ $((count)) -gt $((maxlines)) ]; then
		count="$maxlines"
	fi
	$caller.setvar "$1" $count
}

#
# Returns the portion of the buffer that can currently be displayed.
#
# I.e. it returns the top left part of the buffer cropped to the
# appropriate width and height.
#
# Tabs break this, multibyte characters might result in too strong
# line shortage.
#
# @param &1
#	The displayable buffer portion.
# @param &2
#	The length of the buffer in lines.
#
bsda:tty:Terminal.getDisplayBuffer() {
	local IFS count maxco buffer

	IFS='
'

	# Get the maximum columns from the terminal.
	maxco=$(/usr/bin/tput co 2> /dev/tty || echo 80)
	/usr/bin/tput xn || maxco=$((maxco - 1))

	# Get the number of status lines to display and acquire them
	# from the buffer. Reduce them to the permitted number of collumns.
	$this.getDisplayCount count
	if [ $((count)) -gt 0 ]; then
		buffer="$(
			$this.getBuffer \
			| /usr/bin/awk "
				NR<=$count&&\$0=substr(\$0 \" \", 1, $maxco)END{printf \".\"}")"
	else
		buffer=
	fi

	# Return the buffer.
	$caller.setvar "$1" "${buffer%$IFS.}"
	# Return the buffer length.
	$caller.setvar "$2" $count
}

#
# This turns all terminal operations on /dev/tty off.
#
# The stdout() and stderr() methods are reduced to producing raw output, all
# other public methods simply terminate upon call.
#
bsda:tty:Terminal.deactivate() {
	$this.reset
	$this.setActive
}

#
# Sets the number of status lines to manage for this terminal.
#
# @param 1
#	The number of status lines to use
# @throws bsda_tty_ERR_TERMINAL_LINECOUNT_NOT_UINT
#	Thrown if the provided number of lines is not an unsigned integer
#
bsda:tty:Terminal.use() {
	local IFS active count buffer providers provider index visible

	$this.getActive active
	test -z "$active" && return

	IFS='
'

	# The line count must be a positive integer.
	if ! bsda:obj:isUInt "$1"; then
		bsda_tty_errno=$bsda_tty_ERR_TERMINAL_LINECOUNT_NOT_UINT
		return 1
	fi

	#
	# Two cases, the new number of lines is greater or smaller.
	#
	$this.getCount count
	$this.getProviders providers
	$this.getBuffer buffer
	if [ $count -gt $1 ]; then
		# Lower the count.
		index=0
		for provider in $providers; do
			# Detach obsolete StatusProvider instances.
			if [ $index -ge $1 ]; then
				if bsda:tty:StatusProvider.isInstance "$provider"; then
					$provider.disconnectStatus
				fi
			fi
			index=$((index + 1))
		done
		if [ $1 -gt 0 ]; then
			providers="$(echo "$providers" | /usr/bin/head -n $1 ; echo -n .)"
			providers="${providers%$IFS.}"
			buffer="$(echo "$buffer" | /usr/bin/head -n $1 ; echo -n .)"
			buffer="${buffer%$IFS.}"
		else
			providers=
		fi
	elif [ $count -lt $1 ]; then
		# Increase the count.
		for index in $(/usr/bin/jot $(($1 - count)) $count); do
			if [ $index -eq 0 ]; then
				continue
			fi
			providers="$providers$IFS"
			buffer="$buffer$IFS"
		done
	else
		# Nothing to change.
		return 0
	fi

	# Record the new buffer and provider list, redraw if necessary.
	$this.getVisible visible
	test -n "$visible" && $this.hide
	$this.setProviders "$providers"
	$this.setBuffer "$buffer"
	$this.setCount $1
	test -n "$visible" && $this.show

	return 0
}

#
# Turn off all /dev/tty operations, but still perform the buffer operations.
#
bsda:tty:Terminal.hide() {
	local active visible maxli

	$this.getActive active
	test -z "$active" && return

	$this.getVisible visible

	if [ -n "$visible" ]; then
		/usr/bin/tput AL $(/usr/bin/tput li 2> /dev/tty || echo 24)
		$this.setVisible
	fi > /dev/tty
}

#
# Reactivate /dev/tty operations after a call to the hide() method.
#
bsda:tty:Terminal.show() {
	local active visible

	$this.getActive active
	test -z "$active"  && return

	$this.getVisible visible

	if [ -z "$visible" ]; then
		$this.draw
		$this.setVisible 1
	fi > /dev/tty
}

#
# Refresh the contents of all status lines that have a provider attached.
#
# Causes a redraw of the status lines if they are currently visible.
#
# @param @
#	Each parameter represents a line index or a StatusProvider instance
# @throws bsda_tty_ERR_TERMINAL_STATUSPROVIDER_NOT_IN_LIST
#	Is thrown if an invalid provider was given
# @throws bsda_tty_ERR_TERMINAL_LINEINDEX_NOT_A_NUMBER
#	Is thrown if the given line index is not a number
# @throws bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS
#	Is thrown if an inexistant index line is given
#
bsda:tty:Terminal.refresh() {
	local IFS active provider index line visible count sedcmd buffer
	local providers

	$this.getActive active
	test -z "$active" && return

	IFS='
'

	$this.getCount count
	sedcmd=
	if [ $# -eq 0 ]; then
		# Get the available providers and indexes.
		for provider in $($this.getProviders | /usr/bin/grep -nvx ''); do
			index="${provider%%:*}"
			provider="${provider#*:}"

			$provider.reportStatus line
			sedcmd="${sedcmd:+$sedcmd$IFS}${index}c\\$IFS$line"
		done
	else
		# A list of indexes/providers was specified.
		$this.getProviders providers
		for provider in "$@"; do
			if bsda:tty:StatusProvider.isInstance "$provider"; then
				# A provider was given find the index number
				# (counting from 1).
				index="$(echo "$providers" | /usr/bin/grep -nFx "$provider")"

				if [ -z "$index" ]; then
					bsda_tty_errno=$bsda_tty_ERR_TERMINAL_STATUSPROVIDER_NOT_IN_LIST
					return 1
				fi

				index=${index%%:*}
			else
				# Apparently an index number was given.
				index="$provider"
				if ! bsda:obj:isInt "$index"; then
					bsda_tty_errno=$bsda_tty_ERR_TERMINAL_LINEINDEX_NOT_A_NUMBER
					return 1
				fi
				if [ $index -ge $count -o $index -lt 0 ]; then
					bsda_tty_errno=$bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS
					return 1
				fi
				# Sed counts from 1, so pad the index.
				index="$((index + 1))"
				provider="$(echo "$providers" | /usr/bin/sed "$index!d")"
			fi
			if [ -z "$provider" ]; then
				# If no provider is attached, nothing to be done.
				continue
			fi
			# Get the new status line.
			$provider.reportStatus line
			sedcmd="${sedcmd:+$sedcmd$IFS}${index}c\\$IFS$line\\$IFS"
		done
	fi

	# Update the buffer.
	buffer="$($this.getBuffer | /usr/bin/sed "$sedcmd" ; echo -n .)"
	$this.setBuffer "${buffer%$IFS.}"

	# Redraw status lines.
	$this.getVisible visible
	test -n "$visible" && $this.draw > /dev/tty

	return 0
}

#
# Attach a StatusProvider.
#
# Either attaches the provider to a specific line or if no line is provided
# creates a new one.
#
# Lines are counted from top to bottom, starting at 0.
#
# @param 1
#	The StatusProvider instance to attach
# @param 2
#	The index of the line to attach the provider to, optional
# @throws bsda_tty_ERR_TERMINAL_STATUSPROVIDER_INVALID
#	Is thrown if an invalid provider was given
# @throws bsda_tty_ERR_TERMINAL_LINEINDEX_NOT_A_NUMBER
#	Is thrown if the given line index is not a number
# @throws bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS
#	Is thrown if the given line index is outside of the scope of currently
#	managed lines
#
bsda:tty:Terminal.attach() {
	local IFS active index count buffer providers provider line visible

	$this.getActive active
	test -z "$active" && return

	IFS='
'

	# Check whether a valid StatusProvider has been given.
	provider="$1"
	if ! bsda:tty:StatusProvider.isInstance "$provider"; then
		bsda_tty_errno=$bsda_tty_ERR_TERMINAL_PROVIDER
		return 1
	fi

	index="$2"
	$this.getCount count

	# Set a proper index.
	if bsda:obj:isInt "$index"; then
		if [ $index -ge $count -o $index -lt 0 ]; then
			bsda_tty_errno=$bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS
			return 1
		fi
		$this.detach $index
	elif [ -n "$index" ]; then
		bsda_tty_errno=$bsda_tty_ERR_TERMINAL_LINEINDEX_NOT_A_NUMBER
		return 1
	else
		index=$count
		$this.use $((count + 1))
	fi

	# Update the buffer.
	$provider.reportStatus line
	buffer="$($this.getBuffer | /usr/bin/sed "$(($index + 1))c\\$IFS$line\\$IFS" ; echo -n .)"
	$this.setBuffer "${buffer%$IFS.}"

	# Draw the updated buffer, if necessary.
	$this.getVisible visible
	test -n "$visible" && $this.draw > /dev/tty
	
	# Attach the provider.
	providers="$($this.getProviders | /usr/bin/sed "$((index + 1))c\\$IFS$provider\\$IFS" ; echo -n .)"
	$this.setProviders "${providers%$IFS.}"

	return 0
}

#
# Detach all attached StatusProvider instances and reset the status line buffer.
#
bsda:tty:Terminal.flush() {
	local IFS active providers provider index count

	$this.getActive active
	test -z "$active" && return 0

	IFS='
'

	# Give all attached providers the disconnect notice.
	for provider in $providers; do
		if bsda:tty:StatusProvider.isInstance "$provider"; then
			$provider.disconnectStatus
		fi
	done

	# Create empty buffers.
	$this.getCount count
	providers=
	if [ $count -gt 0 ]; then
		for index in $(/usr/bin/jot $count); do
			providers="$providers$IFS"
		done
	fi
	$this.setBuffer "$providers"
	$this.setProviders "$providers"
}


#
# Detaches the given provider. The screen is not redrawn.
#
# @param 1
#	A line index or a StatusProvider instance
# @throws bsda_tty_ERR_TERMINAL_STATUSPROVIDER_NOT_IN_LIST
#	Is thrown if an invalid provider was given
# @throws bsda_tty_ERR_TERMINAL_LINEINDEX_NOT_A_NUMBER
#	Is thrown if the given line index is not a number
# @throws bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS
#	Is thrown if an inexistant index line is given
#
bsda:tty:Terminal.detach() {
	local IFS active providers provider index sedcmd buffer count

	$this.getActive active
	test -z "$active" && return

	IFS='
'

	$this.getProviders providers
	provider="$1"

	# Either a provider or an index.
	if bsda:tty:StatusProvider.isInstance "$provider"; then
		# The given parameter is a provider.

		# Check whether the provider is attached.
		if ! echo "$providers" | /usr/bin/grep -qFx "$provider"; then
			bsda_tty_errno=$bsda_tty_ERR_TERMINAL_STATUSPROVIDER_NOT_IN_LIST
			return 1
		fi

		# Notify the provider about the disconnect.
		$provider.disconnectStatus

		# Create a sed command that replaces the matching lines.
		# The grep command provides line numbers and the sed command
		# produces a line replacing sed command.
		sedcmd="$(
			echo "$providers" | /usr/bin/grep -Fxn "$provider" \
				| /usr/bin/sed "s/:.*/g/"
		)"

		# Empty the affected lines in the providers list.
		providers="$(echo "$providers" | /usr/bin/sed "$sedcmd" ; echo -n .)"
		$this.setProviders "${providers%$IFS.}"

		# Empty the affected lines in the buffer.
		buffer="$($this.getBuffer | /usr/bin/sed "$sedcmd" ; echo -n .)"
		$this.setBuffer="${buffer%$IFS.}"
	else
		# The given parameter is an index.
		index="$provider"

		# Check whether the index is a valid integer.
		if ! bsda:obj:isInt "$index"; then
			bsda_tty_errno=$bsda_tty_ERR_TERMINAL_LINEINDEX_NOT_A_NUMBER
			return 1
		fi

		# Check whether the index is within the managed range.
		$this.getCount count
		if [ $index -ge $count -o $index -lt 0 ]; then
			bsda_tty_errno=$bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS
			return 1
		fi

		# Get the provider at the index position.
		$this.getProviders providers
		provider="$(echo "$providers" | /usr/bin/sed "$(index + 1)!d")"

		# If there was a provider at the index position, notify it
		# about the disconnect.
		if bsda:tty:StatusProvider.isInstance "$provider"; then
			$provider.disconnectStatus
		fi

		# Empty the line in the buffer.
		buffer="$($this.getBuffer | /usr/bin/sed "$(index + 1))g" ; echo -n .)"
		$this.setBuffer "${buffer%$IFS.}"
		# Empty the line in the providers list.
		providers="$(echo "$providers" | /usr/bin/sed "$((index + 1))g" ; echo -n .)"
		$this.setProviders "${providers%$IFS.}"
	fi
}

#
# Sets a status line by a given index.
#
# The lines are numbered from the top, starting at 0.
#
# The provided text is reduced to the contents of the first line.
#
# @param 1
#	The index line to update
# @param 2
#	The text to set the line to
# @throws bsda_tty_ERR_TERMINAL_LINEINDEX_NOT_A_NUMBER
#	Is thrown if the given line index is not a number
# @throws bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS
#	Is thrown if an inexistant index line is given
#
bsda:tty:Terminal.line() {
	local IFS active visible count pos buffer maxco

	$this.getActive active
	test -z "$active" && return

	# Check the given index.
	$this.getCount count
	pos="$1"
	if ! bsda:obj:isInt "$pos"; then
		bsda_tty_errno=$bsda_tty_ERR_TERMINAL_LINEINDEX_NOT_A_NUMBER
		return 1
	fi
	if [ $1 -ge $count -o $pos -lt 0 ]; then
		bsda_tty_errno=$bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS
		return 1
	fi

	IFS='
'


	# Check if the line can be displayed.
	$this.getVisible visible
	$this.getDisplayCount count
	if [ -n "$visible" -a $pos -lt $count ]; then
		# Crop the line to display.
		maxco=$(/usr/bin/tput co 2> /dev/tty || echo 80)
		/usr/bin/tput xn || maxco=$((maxco - 1))

		# Jump to the right line.
		/usr/bin/tput vi cr up DO $((pos + 1)) ce
		# Draw it.
		printf "%.${maxco}s" "${2%%$IFS*}"
		# Return the cursor to its origin.
		/usr/bin/tput cr UP $((pos + 1)) do ve
	fi > /dev/tty

	# Store the new line in the status line buffer.
	buffer="$($this.getBuffer | /usr/bin/awk "NR==$((pos + 1)){\$0=\"${2%%$IFS*}\"}1;END{printf \".\"}")"
	$this.setBuffer "${buffer%$IFS.}"

	return 0
}

#
# Outputs text on stdout without destroying status line display.
#
# The text to output can be given as command arguments or through a pipe.
# Arguments take precedence over piped input.
#
# Double wide multibyte characters might break this.
#
# @param @
#	The text to output
#
bsda:tty:Terminal.stdout() {
	local IFS output draw active visible count maxli maxco lines
	local glitch tabstops discard

	IFS='
'

	# Check whether tty operations are activated.
	$this.getActive active
	$this.getVisible visible

	# Take output either from arguments, or if none are provided from
	# stdin.
	if [ $# -gt 0 ]; then
		output="$@"
	else
		output="$(/bin/cat)"
	fi
	# Make sure the output ends with a newline.
	output="${output%$IFS}$IFS"

	#
	# Get all the stuff needed to know for flicker free output.
	#
	maxli=0
	if [ -n "$active" ]; then
		# Get the maximum lines and columns from the terminal.
		maxli=$(/usr/bin/tput li 2> /dev/tty || echo 24)
		maxco=$(/usr/bin/tput co 2> /dev/tty || echo 80)

		# Get the tab stop width.
		tabstops=$(/usr/bin/tput it || echo 8)

		# Set this to 0 if the terminal eats the newline glitch,
		# otherwise set it to 1.
		/usr/bin/tput xn
		glitch=$?
	fi

	#
	# Perform all the fancy terminal handling like output faking, status
	# line drawing and cursor placing.
	#

	# Get the number of status lines to display and acquire them
	# from the buffer.
	$this.getDisplayBuffer buffer count

	# Only perform all that fancy stuff in visible mode.
	if [ -n "$active" -a -n "$visible" -a $((maxli)) -gt 1 -a $((count)) -gt 0 ]; then
		# Get the maximum lines left for output.
		if [ $((count)) -eq 0 ]; then
			maxli=$((maxli - 1))
		else
			maxli=$((maxli - count))
		fi

		# Output output chunks until nothing is left to output.
		while [ -n "$output" ]; do
			# Get the lines to output this round.
			draw="$(
				echo -n "$output" \
					| ${bsda_dir:-.}/head.awk $maxco $maxli $tabstops $glitch
			)"
			# The number of lines is returned by the script.
			lines="${draw##*.}"
			draw="${draw%.*}"

			# Filter characters that might endanger glob pattern
			# substitution.
			discard="$(echo -n "$draw." | /usr/bin/tr '#[]*{}' '??????')"
			discard="${discard%.}"

			# Remove the current draw from the remaining output.
			output="${output#$discard}"

			# Move the status lines down behind the position where
			# the output will end.
			/usr/bin/tput AL $lines > /dev/tty

			# Put the output on stdout.
			echo -n "$draw"
			( /usr/bin/tput vi cr
			  echo -n "$buffer"
			  /usr/bin/tput cr UP $count do ve
			) > /dev/tty
		done
	else
		# Simply output stuff.
		echo -n "$output"
	fi
}

#
# Does the same as the stdout() method on stderr.
#
# @param @
#	The text to output
#
bsda:tty:Terminal.stderr() {
	bsda:tty:Terminal.stdout "$@" 1>&2
}

