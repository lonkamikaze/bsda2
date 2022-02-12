test -n "$_bsda_tty_" && return 0
readonly _bsda_tty_=1

. ${bsda_dir:-.}/bsda_obj.sh

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
# Attach a filter to a file descriptor.
#
bsda:obj:createClass bsda:tty:Filter \
	r:private:desc  "The filter descriptor" \
	r:private:fifo  "The named pipe to hook redirects into" \
	i:private:init  "Attach the filter" \
	c:private:free  "Terminate the filter"

#
# Dispatch the filter and redirect the requested output into it.
#
# @param 1
#	The file descriptor to attach to the filter
# @param @
#	The filter command (see eval)
#
bsda:tty:Filter.init() {
	local fifo
	# Setup a named pipe
	setvar ${this}fifo "$(/usr/bin/mktemp -ut bsda:tty:Filter)" || return $?
	$this.getFifo fifo
	/usr/bin/mkfifo -m 0600 "${fifo}" || return $?
	# Dispatch the filter
	(shift; eval "$@") < "$fifo" &
	# Redirect the requested file descriptor into the filter
	setvar ${this}desc $(($1))
	eval "exec $(($1))>> ${fifo}"
	# Clean up the named pipe
	/bin/rm "$fifo"
	unset ${this}fifo
}

#
# Release the named pipe and kill the filter process.
#
bsda:tty:Filter.free() {
	local fifo desc
	# Cleanup fifo in case of incomplete initialisation
	$this.getFifo fifo
	if [ -n "$fifo" ]; then
		/bin/rm "$fifo" 2>&-
	fi
	# Kill filter process
	$this.getDesc desc
	if [ -n "$desc" ]; then
		eval "exec $((desc))>&-"
	fi
}

#
# Provides terminal output.
#
# This provides n status lines directly on the terminal, i.e. they
# are not affected by redirecting stdout or stderr. It also provides
# output on stdout and stderr without messing up the status lines.
#
bsda:obj:createClass bsda:tty:Terminal \
	a:private:Filter1=bsda:tty:Filter \
	a:private:Filter2=bsda:tty:Filter \
	r:private:stLines   "The number of status lines" \
	r:private:drLines   "The number of status lines to draw" \
	x:public:winch      "Update window signal handler" \
	i:private:init      "Take over the terminal output" \
	x:public:use        "Set number of status lines" \
	x:public:line       "Set a status line" \
	c:public:deactivate "Deactivate status lines" \
	x:public:stdout     "Print to stdout" \
	x:public:stderr     "Print to stderr" \
	x:public:filter     "Install an optional output filter" \
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
	$this.refresh
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
		unset ${this}line$((lines -= 1))
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
	echo -n "$2"
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
	(
		# tput       vi.......
		printf '%b' '\033[?25l\r' $($class:repeat $lineno '\n')
		# tput  RA......  ce....  SA......
		printf '\033[?7l%s\033[K\r\033[?7h' "$*"
		# tput                               up...    ve...............
		printf '%b' $($class:repeat $lineno '\033M') '\033[34h\033[?25h'
	) > /dev/tty
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
	$this.refresh
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
# Install an output filter on the requested output.
#
# Filters are permanent, if the Terminal instance is deleted the
# outputs are closed and remain unusable until redirected.
#
# @param 1
#	The file descriptor to filter, 1 (stdout) or 2 (stderr)
# @retval 0
#	Attaching the filter was successful
# @retval 1
#	Invalid file descriptor (must be 1 or 2)
# @retval 2
#	A filter was already attached to the output
# @retval 3
#	Filter setup failed
#
bsda:tty:Terminal.filter() {
	local filter
	case "$1" in
	1 | 2)
		$this.Filter$1 filter
		test -z "$filter" || return 2
		bsda:tty:Filter ${this}Filter$1 "$@" || return 3
	;;
	*)
		return 1
	;;
	esac
}

#
# Draw all the status lines.
#
bsda:tty:Terminal.refresh() (
	if [ $((${this}drLines)) -le 0 ]; then
		return 0
	fi
	exec > /dev/tty
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
)
