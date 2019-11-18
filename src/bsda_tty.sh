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
# | Command            | Short    | Escape        | Problems              |
# |--------------------|----------|---------------|-----------------------|
# | save_cursor        | sc       | \e7           |                       |
# | restore_cursor     | rc       | \e8           |                       |
# | cursor_address     | cm #1 #2 | \e[#2;#1H     | Escape counts from 1  |
# | cursor_home        | ho       | \e[H          |                       |
# | columns            | co => #  |               |                       |
# | lines              | li => #  |               |                       |
# | clr_eol            | ce       | \e[K          |                       |
# | clr_eos            | cd       | \e[J          |                       |
# | delete_line        | dl       | \e[M          |                       |
# | parm_insert_line   | AL #1    | \e[#1L        |                       |
# | insert_line        | al       | \e[L          |                       |
# | cursor_invisible   | vi       | \e[?25l       |                       |
# | cursor_normal      | ve       | \e[34h\e[?25h |                       |
# | cursor_visible     | vs       | \e[34l        |                       |
# | parm_down_cursor   | DO #1    | \e[#1B        | DO 0 glitches in tmux |
# | parm_up_cursor     | UP #1    | \e[#1A        | UP 0 glitches in tmux |
# | carriage_return    | cr       | \r            |                       |
# | newline            | nw       | \eE           |                       |
# | cursor_down        | do       | \n            |                       |
# | cursor_up          | up       | \eM           |                       |
# | eat_newline_glitch | xn       |               |                       |
# | init_tabs          | it => #  |               |                       |
# | enter_am_mode      | SA       | \e[?7h        | tput SA does not work |
# | exit_am_mode       | RA       | \e[?7l        | tput RA does not work |
# | enter_ca_mode      | ti       | \e[?1049h     |                       |
# | exit_ca_mode       | te       | \e[?1049l     |                       |
#

#
# Provides terminal output.
#
# This provides n status lines directly on the terminal, i.e. they
# are not affected by redirecting stdout or stderr. It also provides
# output on stdout and stderr without messing up the status lines.
#
bsda:obj:createClass bsda:tty:Terminal \
	r:private:stLines   "The number of status lines" \
	r:private:drLines   "The number of status lines to draw" \
	x:public:winch      "Update window signal handler" \
	i:public:init       "Take over the terminal output" \
	x:public:use        "Set number of status lines" \
	x:public:line       "Set a status line" \
	c:public:deactivate "Deactivate status lines" \
	x:public:stdout     "Print to stdout" \
	x:public:stderr     "Print to stderr" \
	x:private:refresh   "Redraw status lines"

#
# SIGWINCH handler.
#
# Caps the number of status lines to draw to half of the terminal height
# and calls refresh().
#
bsda:tty:Terminal.winch() {
	local teLines
	trap '' WINCH
	teLines=$(($(/usr/bin/tput li 2> /dev/tty || echo 24)))
	# Use at most half of the available terminal space
	setvar ${this}drLines $((${this}stLines < (teLines / 2) ? ${this}stLines : (teLines / 2)))
	$this.refresh > /dev/tty
	trap "$this.winch" WINCH
}

#
# Setup terminal.
#
bsda:tty:Terminal.init() {
	if [ -w /dev/tty ]; then
		$this.use 0
	else
		$this.deactivate
	fi
}

#
# Changes the number of status lines.
#
# Updates the number of desired status lines, sets the number of
# actual status lines to draw and redraws the status.
#
# @param 1
#	The requested number of status lines
#
bsda:tty:Terminal.use() {
	local lines
	$this.getStLines lines
	# delete no longer needed status lines
	while [ $((lines)) -gt $(($1)) ]; do
		lines=$((lines - 1))
		unset ${this}line${lines}
	done
	setvar ${this}stLines $(($1))
	$this.winch
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
bsda:tty:Terminal:repeat() {
	if [ $1 -le 0 ]; then
		return
	fi
	echo "$2"
	bsda:tty:Terminal:repeat $(($1 - 1)) "$2"
}

#
# Draw the given status line.
#
# This jumps to the given line and draws it.
#
# @param 1
#	The status line number to draw on
# @param *
#	The status line contents to draw
#
bsda:tty:Terminal.line() {
	if [ $(($1)) -ge $((${this}drLines)) ] || [ $(($1)) -lt 0 ]; then
		return
	fi
	local lineno line
	lineno=$(($1))
	line=${this}line$(($1))
	shift
	setvar $line "$*"
	# tput       vi.......
	printf '%b' '\033[?25l\r' $($class:repeat $lineno '\n')
	# tput        RA......  ce...   SA.....
	eval "printf '\033[?7l%s\033[K\r\033[?7h' \"\$*\""
	# tput                               up...    ve...............
	printf '%b' $($class:repeat $lineno '\033M') '\033[34h\033[?25h'
}

#
# Clear status lines, turn cursor visible  and replace methods with
# dummies.
#
# Note that stdout() and stderr() still perform output.
#
bsda:tty:Terminal.deactivate() {
	local stLines
	# delete stored status lines
	$this.getStLines stLines
	if [ $((stLines)) -gt 0 ]; then
		$this.use 0
		# tput      cd..ve...........
		echo -n $'\r\e[J\e[34h\e[?25h' > /dev/tty
	fi
	# restore signal default
	trap - WINCH
	# replace public methods with dummies
	eval "$this.winch() { :; }"
	eval "$this.use() { :; }"
	eval "$this.line() { :; }"
	eval "$this.stdout() { echo \"\$*\"; }"
	eval "$this.stderr() { echo \"\$*\" >&2; }"
}

#
# Print on stdout.
#
# Clears the status lines, prints the requested output and redraws the
# status lines.
#
# @param IFS
#	The first character in IFS is used to join multiple arguments,
#	if unset a single space is used
# @param *
#	The strings to output
#
bsda:tty:Terminal.stdout() {
	echo -n $'\e[J' > /dev/tty
	echo "$*"
	$this.refresh > /dev/tty
}

#
# Print on stderr.
#
# Clears the status lines, prints the requested output and redraws the
# status lines.
#
# @param IFS
#	The first character in IFS is used to join multiple arguments,
#	if unset a single space is used
# @param *
#	The strings to output
#
bsda:tty:Terminal.stderr() {
	$class.stdout "$@" >&2
}

#
# Draw all the status lines.
#
# The caller is responsible for redirecting the output to /dev/tty.
#
bsda:tty:Terminal.refresh() {
	if [ $((${this}drLines)) -le 0 ]; then
		return 0
	fi
	local i
	i=$((${this}drLines - 1))
	# tput       vi.......                              RA......
	printf '%b' '\033[?25l\r' $($class:repeat $i '\n') '\033[?7l'
	while [ $i -gt 0 ]; do
		# tput          ce....  up...
		eval "printf '%s\033[K\r\033M' \"\$${this}line$i\""
		i=$((i - 1))
	done
	# tput          ce....  SA......ve...............
	eval "printf '%s\033[K\r\033[?7h\033[34h\033[?25h' \"\$${this}line0\""
}

#
# Provides asynchronous terminal output.
#
# This provides n status lines directly on the terminal, i.e. they
# are not affected by redirecting stdout or stderr. It also provides
# output on stdout and stderr without messing up the status lines.
#
bsda:obj:createClass bsda:tty:Async \
	a:private:Fifo=bsda:fifo:Fifo \
	r:private:active    "Whether status line output is active" \
	r:private:dpid      "The PID of the daemon process" \
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
	if [ -w /dev/tty ]; then
		bsda:fifo:Fifo ${this}Fifo || return $?
		setvar ${this}active 1
		$class.daemon &
		setvar ${this}dpid $!
	fi
}

#
# Deactivate the daemon and remove the fifo.
#
bsda:tty:Async.clean() {
	$this.deactivate
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
	$($this.Fifo).sink "printf 'use %d\n' $(($1))"
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
			local NL str line
			NL=$'\n'
			str=\"\$(echo -n \"\${2%%\$NL*}\" | bsda:obj:escape)\"
			line=\$((\$1))
			$($this.Fifo).sink 'echo \"line\$line \$str\"'
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
		$($this.Fifo).sink echo exit
		# Reset self-optimising functions
		bsda:tty:Async.line
		bsda:tty:Async.stdout
		bsda:tty:Async.stderr
		# Wait for daemon to exit
		wait $($this.getDpid)
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
			$($this.Fifo).sink 'echo \"stdout \$str\"'
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
			$($this.Fifo).sink 'echo \"stderr \$str\"'
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
# @param lines
#	Set to the available number of lines
# @param drawLines
#	The number of status lines to actually draw
# @param statusLines
#	The number of status lines requested
#
bsda:tty:Async.daemon_winch() {
	lines=$(/usr/bin/tput li 2> /dev/tty || echo 24)
	# Use at most half of the available terminal space
	drawLines=$((statusLines < (lines / 2) ? statusLines : (lines / 2)))
}

#
# Initialises globals required in the daemon process.
#
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
	$this.Fifo fifo
	# Handle signals
	trap "trap '' HUP INT TERM;$fifo.sink echo exit" HUP INT TERM
	trap "trap '' WINCH;$fifo.sink echo winch" WINCH
	statusLines=0
	IFS=$' \t\n'
	readonly fifo IFS
}

#
# Draw all the status lines.
#
# The caller is responsible for redirecting the output to /dev/tty.
#
# @param drawLines
#	The number of status lines to draw
# @param line0 line1 line...
#	The status line buffers
#
bsda:tty:Async.daemon_drawlines() {
	if [ $((drawLines)) -le 0 ]; then
		return 0
	fi
	local i
	i=$((drawLines - 1))
	# tput       vi.......                                     RA......
	printf '%b' '\033[?25l\r' $($class.daemon_repeat $i '\n') '\033[?7l'
	while [ $i -gt 0 ]; do
		# tput          ce....  up...
		eval "printf '%s\033[K\r\033M' \"\$line$i\""
		i=$((i - 1))
	done
	# tput    ce....  SA......ve...............
	printf '%s\033[K\r\033[?7h\033[34h\033[?25h' "$line0"
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
# @param line0 line1 line...
#	The status line buffers
#
bsda:tty:Async.daemon_drawline() {
	if [ $1 -ge $drawLines ] || [ $1 -lt 0 ]; then
		return
	fi
	# tput       vi.......
	printf '%b' '\033[?25l\r' $($class.daemon_repeat $1 '\n')
	eval "printf '\033[?7l%s\033[K\r\033[?7h' \"\$line$1\""
	# tput                                 up...    ve...............
	printf '%b' $($class.daemon_repeat $1 '\033M') '\033[34h\033[?25h'
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
	# tput      cd..ve...........
	echo -n $'\r\e[J\e[34h\e[?25h' > /dev/tty
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
	# tput    cd..
	echo -n $'\e[J' > /dev/tty
	echo "$1"
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
		$fifo.source read -r cmd arg
		retval=$?
		if [ $retval -gt 128 ]; then
			# Retry read if interrupted by a signal
			continue
		elif [ $retval -ne 0 ]; then
			$class.daemon_stdout "bsda:tty:Async.daemon: ERROR: Read from pipe returned: $retval" >&2
			exit $retval
		fi
		arg="$(printf "$arg")" # Deserialise
		case "$cmd" in
		line*)
			setvar "$cmd" "$arg"
			$class.daemon_drawline ${cmd#line} > /dev/tty
		;;
		stdout)
			$class.daemon_stdout "$arg"
		;;
		stderr)
			$class.daemon_stdout "$arg" >&2
		;;
		use)
			$class.daemon_use "$arg"
		;;
		exit)
			exit 0
		;;
		winch)
			trap "trap '' WINCH;$fifo.sink echo winch" WINCH
			$class.daemon_winch
		;;
		'')
			# This seems to happen on SIGINT/SIGHUP/SIGTERM
		;;
		*)
			$class.daemon_stdout "bsda:tty:Async.daemon: WARNING: Illegal command received: $(echo -n "$cmd" | bsda:obj:escape)" >&2
		;;
		esac
	done
}
