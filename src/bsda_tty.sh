test -n "$_bsda_tty_" && return 0
readonly _bsda_tty_=1

. ${bsda_dir:-.}/bsda_fifo.sh

#
# A package for controlling the terminal and mixing status output on
# /dev/tty with regular output on /dev/stdout and /dev/stderr.
#
# Output duplication has been removed in favour of tee(1).
#
# Tested on:
#
# | Terminal     | TERM   |
# |--------------|--------|
# | xterm        | xterm  |
# | console      | xterm  |
# | rxvt-unicode | rxvt   |
# | tmux         | screen |
#

#
# A list of useful termcap(5) capabilities, used with tput(1):
#
# | Command            | Short    | Problems              |
# |--------------------|----------|-----------------------|
# | save_cursor        | sc       |                       |
# | restore_cursor     | rc       |                       |
# | cursor_address     | cm #1 #2 |                       |
# | cursor_home        | ho       |                       |
# | columns            | co => #  |                       |
# | lines              | li => #  |                       |
# | clr_eol            | ce       |                       |
# | clr_eos            | cd       |                       |
# | delete_line        | dl       |                       |
# | parm_insert_line   | AL #1    |                       |
# | insert_line        | al       |                       |
# | cursor_invisible   | vi       |                       |
# | cursor_normal      | ve       |                       |
# | cursor_visible     | vs       |                       |
# | parm_down_cursor   | DO #1    | DO 0 glitches in tmux |
# | parm_up_cursor     | UP #1    | UP 0 glitches in tmux |
# | carriage_return    | cr       |                       |
# | newline            | nw       |                       |
# | cursor_down        | do       |                       |
# | cursor_up          | up       |                       |
# | eat_newline_glitch | xn       |                       |
# | init_tabs          | it => #  |                       |
#

#
# Provides asynchronous terminal output.
#
# This provides n status lines directly on the terminal, i.e. they
# are not affected by redirecting stdout or stderr. It also provides
# output on stdout and stderr without messing up the status lines.
#
bsda:obj:createClass bsda:tty:Async \
	r:private:fifo      "The FIFO to communicate through" \
	r:private:active    "Whether status line output is active" \
	i:private:init      "Set up asynchronous output process" \
	c:private:clean     "Terminate the output process" \
	x:public:use        "Set number of status lines" \
	x:public:line       "Set a status line" \
	x:public:deactivate "Deactivate status lines" \
	x:public:stdout     "Print to stdout" \
	x:public:stderr     "Print to stderr"

#
# Setup terminal control daemon.
#
# Sets up a bsda:tty:Async.daemon() instance that controls the terminal
# and receives commands through a fifo.
#
bsda:tty:Async.init() {
	bsda:fifo:Fifo ${this}fifo
	setvar ${this}active
	if [ -w /dev/tty ]; then
		setvar ${this}active 1
		$class.daemon &
	fi
}

#
# Deactivate the daemon and remove the fifo.
#
bsda:tty:Async.clean() {
	local fifo
	$this.deactivate
	$this.getFifo fifo
	$fifo.delete
}

#
# Sets the number of status lines to use.
#
# @param 1
#	The number of lines
#
bsda:tty:Async.use() {
	if eval "[ -z \"\$${this}active\" ]"; then
		return
	fi
	$($this.getFifo).sink "printf 'use%d\n' $(($1))"
}

#
# Sets the status of a status line.
#
# @param 1
#	The status line to set
# @param 2
#	The string to set the status line to
#
bsda:tty:Async.line() {
	# Redefine into minimal function
	if eval "[ -n \"\$${this}active\" ]"; then
		eval "$this.line() {
			local NL
			NL='
'
			$($this.getFifo).sink \"printf 'line%d=%s\n' \$((\$1)) '\$(echo \"\${2%%\$NL*}\" | bsda:obj:escape)'\"
		}"
	else
		eval "$this.line() {
			:
		}"
	fi
	# Call the redefined function
	if [ -n "$*" ]; then
		$this.line "$@"
	fi
}

#
# Disable status output and stop the daemon.
#
# Deactivating the daemon is not reversible, but the stdout() and
# stderr() methods still produce synchronous output.
#
bsda:tty:Async.deactivate() {
	if eval "[ -n \"\$${this}active\" ]"; then
		setvar ${this}active
		$($this.getFifo).sink echo exit
		# Reset self-optimising functions
		bsda:tty:Async.line
		bsda:tty:Async.stdout
		bsda:tty:Async.stderr
	fi
}

#
# Output on stdout.
#
# @param IFS
#	The first character in IFS is used to join multiple arguments,
#	if unset a single space is used
# @param *
#	The strings to output
#
bsda:tty:Async.stdout() {
	# Redefine into minimal function
	if eval "[ -n \"\$${this}active\" ]"; then
		eval "$this.stdout() {
			local str
			str=\"\$(echo \"\$*\" | bsda:obj:escape)\"
			$($this.getFifo).sink \"echo \\\"stdout\\\$str\\\"\"
		}"
	else
		eval "$this.stdout() {
			echo \"\$*\"
		}"
	fi
	# Call the redefined function
	if [ -n "$*" ]; then
		$this.stdout "$@"
	fi
}

#
# Output on stderr.
#
# @param IFS
#	The first character in IFS is used to join multiple arguments,
#	if unset a single space is used
# @param *
#	The strings to output
#
bsda:tty:Async.stderr() {
	if eval "[ -n \"\$${this}active\" ]"; then
		eval "$this.stderr() {
			local str
			str=\"\$(echo \"\$*\" | bsda:obj:escape)\"
			$($this.getFifo).sink \"echo \\\"stderr\\\$str\\\"\"
		}"
	else
		eval "$this.stderr() {
			echo \"\$*\"
		}"
	fi
	# Call the redefined function
	if [ -n "$*" ]; then
		$this.stderr "$@"
	fi
}

#
# Updates the number of terminal columns and lines.
#
# This is called during daemon startup and use() is called.
#
# @param cols
#	Set to the available number of columns
# @param lines
#	Set to the available number of lines
# @param drawLines
#	The number of status lines to actually draw
# @param statusLines
#	The number of status lines requested
#
bsda:tty:Async.daemon_winch() {
	cols=$(/usr/bin/tput co 2> /dev/tty || echo 80)
	/usr/bin/tput xn 2> /dev/tty || cols=$((cols - 1))
	lines=$(/usr/bin/tput li 2> /dev/tty || echo 24)
	# Use at most half of the available terminal space
	drawLines=$((statusLines < (lines / 2) ? statusLines : (lines / 2)))
}

#
# Initialises globals required in the daemon process.
#
# @param cols
#	See bsda:tty:Async.daemon_winch()
# @param lines
#	See bsda:tty:Async.daemon_winch()
# @param drawLines
#	See bsda:tty:Async.daemon_winch()
# @param fifo
#	The FIFO the commands are coming from
# @param statusLines
#	The initial amount of status lines (0)
# @param IFS
#	Set to the newline
# @param trapped
#	Initially empty
#
bsda:tty:Async.daemon_startup() {
	trap "$class.daemon_deactivate" EXIT
	$class.daemon_winch
	$this.getFifo fifo
	# Handle signals
	trap "trap '' HUP INT TERM;$fifo.sink echo exit" HUP INT TERM
	trap "trap '' WINCH;$fifo.sink echo winch" WINCH
	statusLines=0
	IFS='
'
	readonly fifo IFS
}

#
# Draw all the status lines.
#
# The caller is responsible for redirecting the output to /dev/tty.
#
# @param drawLines
#	The number of status lines to draw
# @param cols
#	The number of columns available to draw
# @param line0 line1 line...
#	The status line buffers
#
bsda:tty:Async.daemon_drawlines() {
	/usr/bin/tput vi cr cd
	i=0
	while [ $i -lt $((drawLines - 1)) ]; do
		eval "printf '%.${cols}s\n' \"\$line$i\""
		i=$((i + 1))
	done
	if [ $drawLines -gt 0 ]; then
		eval "printf '%.${cols}s\r' \"\$line$i\""
	fi
	/usr/bin/tput $($class.daemon_repeat $((statusLines - 1)) up) ve
}

#
# Prints a string a given number of times.
#
# This can be used to generate repeated function arguments.
#
# @param 1
#	Number of repetitions
# @param 2
#	String to repeat
#
bsda:tty:Async.daemon_repeat() {
	if [ $1 -le 0 ]; then
		return
	fi
	echo "$2"
	bsda:tty:Async.daemon_repeat $(($1 - 1)) "$2"
}

#
# Draw the given status line.
#
# This jumps to the given line and redraws it from the buffer.
#
# @param 1
#	The status line number to draw on
# @param drawLines
#	The number of status lines that may be drawn
# @param cols
#	The number of available columns
# @param line0 line1 line...
#	The status line buffers
#
bsda:tty:Async.daemon_drawline() {
	if [ $1 -ge $drawLines -o $1 -lt 0 ]; then
		return
	fi
	/usr/bin/tput vi cr $($class.daemon_repeat $1 do)
	eval "printf '%.${cols}s' \"\$line$1\""
	/usr/bin/tput ce cr $($class.daemon_repeat $1 up) ve
}

#
# Changes the number of status lines.
#
# Updates the number of desired status lines, sets the number of
# actual status lines to draw and redraws the status.
#
# @param 1
#	The requested number of status lines
# @param statusLines
#	Set to the requested number
# @param drawLines
#	See bsda:tty:Async.daemon_winch()
#
bsda:tty:Async.daemon_use() {
	statusLines=$(($1))
	# Update drawLines
	$class.daemon_winch
}

#
# Cleanup function.
#
# Clear the status lines, and turn the cursor visible.
#
bsda:tty:Async.daemon_deactivate() {
	/usr/bin/tput cr cd ve > /dev/tty
}

#
# Print on stdout.
#
# Clears the status lines, prints the requested output and redraws the
# status lines.
#
# @param 1
#	A quoted, escaped string, such as bsda:obj:escape() produces
#
bsda:tty:Async.daemon_stdout() {
	/usr/bin/tput cd > /dev/tty
	eval "echo $1"
	$class.daemon_drawlines > /dev/tty
}

#
# The output daemon.
#
# Receives and executes commands from the daemon.
#
bsda:tty:Async.daemon() {
	$class.daemon_startup
	while true; do
		$fifo.source read -r cmd
		retval=$?
		if [ $retval -gt 128 ]; then
			# Retry read if interrupted by a signal
			continue
		elif [ $retval -ne 0 ]; then
			$class.daemon_stdout "bsda:tty:Async.daemon: ERROR: Read from pipe returned: $retval" >&2
			exit $retval $retval
		fi
		case "$cmd" in
		line*)
			eval "$cmd"
			cmd="${cmd#line}"
			$class.daemon_drawline ${cmd%%=*} > /dev/tty
		;;
		stdout*)
			$class.daemon_stdout "${cmd#stdout}"
		;;
		stderr*)
			$class.daemon_stdout "${cmd#stderr}" >&2
		;;
		use*)
			$class.daemon_use "${cmd#use}"
		;;
		exit)
			exit 0
		;;
		winch)
			trap "trap '' WINCH;$fifo.sink echo winch" WINCH
			$class.daemon_winch
		;;
		*)
			$class.daemon_stdout "bsda:tty:Async.daemon: WARNING: Illegal command received: $(echo "$cmd" | bsda:obj:escape)" >&2
		;;
		esac
	done
}

