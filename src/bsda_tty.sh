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

#
# Provides asynchronous terminal output.
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

bsda:tty:Async.init() {
	bsda:fifo:Fifo ${this}fifo
	setvar ${this}active
	if [ -w /dev/tty ]; then
		setvar ${this}active 1
		$class.daemon &
	fi
}

bsda:tty:Async.clean() {
	local fifo
	$this.deactivate
	$this.getFifo fifo
	$fifo.delete
}

bsda:tty:Async.use() {
	if eval "[ -z \"\$${this}active\" ]"; then
		return
	fi
	$($this.getFifo).sink "printf 'use%d\n' $(($1))"
}

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

bsda:tty:Async.stdout() {
	# Redefine into minimal function
	if eval "[ -n \"\$${this}active\" ]"; then
		eval "$this.stdout() {
			$($this.getFifo).sink \"echo 'stdout\$(echo \"\$1\" | bsda:obj:escape)'\"
		}"
	else
		eval "$this.stdout() {
			echo \"\$1\"
		}"
	fi
	# Call the redefined function
	if [ -n "$*" ]; then
		$this.stdout "$@"
	fi
}

bsda:tty:Async.stderr() {
	if eval "[ -n \"\$${this}active\" ]"; then
		eval "$this.stderr() {
			$($this.getFifo).sink \"echo 'stderr\$(echo \"\$1\" | bsda:obj:escape)'\"
		}"
	else
		eval "$this.stderr() {
			echo \"\$1\"
		}"
	fi
	# Call the redefined function
	if [ -n "$*" ]; then
		$this.stderr "$@"
	fi
}

#
# @param cols
# @param lines
#
bsda:tty:Async.daemon_winch() {
	cols=$(/usr/bin/tput co 2> /dev/tty || echo 80)
	/usr/bin/tput xn 2> /dev/tty || cols=$((cols - 1))
	lines=$(/usr/bin/tput li 2> /dev/tty || echo 24)
	# Use at most half of the available terminal space
	drawLines=$((statusLines < (lines / 2) ? statusLines : (lines / 2)))
}

#
# @param cols
# @param lines
# @param fifo
# @param statusLines
#
bsda:tty:Async.daemon_startup() {
	trapped=
	trap "$class.daemon_deactivate" EXIT
	trap "exit 1" HUP INT TERM
	$class.daemon_winch
	$this.getFifo fifo
	statusLines=0
	IFS='
'
	readonly fifo IFS
}

#
# @param statusLines
# @param cols
# @param line0 line1 line...
#
bsda:tty:Async.daemon_drawlines() {
	/usr/bin/tput vi cr
	i=0
	while [ $i -lt $((statusLines - 1)) ]; do
		eval "printf '%.${cols}s\n' \"\$line$i\""
		i=$((i + 1))
	done
	if [ $statusLines -gt 0 ]; then
		eval "printf '%.${cols}s\r' \"\$line$i\""
	fi
	/usr/bin/tput $($class.daemon_repeat $((statusLines - 1)) up) ve
}

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
# @param 1
# @param statusLines
# @param cols
# @param line0 line1 line...
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
# @param statusLines
# @param lines
#
bsda:tty:Async.daemon_use() {
	statusLines=$(($1))
	# Update drawLines
	$class.daemon_winch
	/usr/bin/tput cd > /dev/tty
	$class.daemon_drawlines > /dev/tty
}

#
# @param lines
#
bsda:tty:Async.daemon_deactivate() {
	/usr/bin/tput cr cd ve > /dev/tty
}

#
# @param lines
#
bsda:tty:Async.daemon_stdout() {
	/usr/bin/tput cd > /dev/tty
	eval "echo $1"
	$class.daemon_drawlines > /dev/tty
}

bsda:tty:Async.daemon() {
	$class.daemon_startup
	while $fifo.source read -r cmd; do
		# Delay signal handling while drawing
		trap "trapped=1" HUP INT TERM
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
		*)
			$class.daemon_stdout "bsda:tty:Async.daemon: WARNING: Illegal command received: $(echo "$cmd" | bsda:obj:escape)" >&2
		;;
		esac
		# Handle SIGINT and SIGTERM
		trap "exit 1" HUP INT TERM
		if [ -n "$trapped" ]; then
			exit 1
		fi
	done
}

