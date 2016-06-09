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
	if eval "[ -z \"\$${this}active\" ]"; then
		return
	fi
	local NL
	NL='
'
	$($this.getFifo).sink "printf 'line%d=%s\n' $(($1)) '$(echo "${2%%$NL*}" | bsda:obj:escape)'"
}

bsda:tty:Async.deactivate() {
	if eval "[ -n \"\$${this}active\" ]"; then
		setvar ${this}active
		$($this.getFifo).sink echo exit
	fi
}

bsda:tty:Async.stdout() {
	if eval "[ -n \"\$${this}active\" ]"; then
		$($this.getFifo).sink "printf 'stdout%s\n' '$(echo "$1" | bsda:obj:escape)'"
	else
		echo "$1"
	fi
}

bsda:tty:Async.stderr() {
	if eval "[ -n \"\$${this}active\" ]"; then
		$($this.getFifo).sink "printf 'stderr%s\n' '$(echo "$1" | bsda:obj:escape)'"
	else
		echo "$1" >&2
	fi
}

#
# @param cols
# @param lines
#
bsda:tty:Async.daemon_winch() {
	cols=$(/usr/bin/tput co 2> /dev/tty || echo 80)
	/usr/bin/tput xn || cols=$((cols - 1))
	lines=$(/usr/bin/tput li 2> /dev/tty || echo 24)
}

#
# @param cols
# @param lines
# @param fifo
# @param statusLines
#
bsda:tty:Async.daemon_startup() {
	trap $class.daemon_deactivate EXIT
	trap "$class.daemon_deactivate;exit" INT TERM
	trap $class.daemon_winch WINCH
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
	if [ $1 -ge $statusLines -o $1 -lt 0 ]; then
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
	statusLines=$((lines / 2 > $1 ? $1 : lines / 2))
	/usr/bin/tput $($class.daemon_repeat $lines al) > /dev/tty
	$class.daemon_drawlines > /dev/tty
}

#
# @param lines
#
bsda:tty:Async.daemon_deactivate() {
	/usr/bin/tput $($class.daemon_repeat $lines al) ve > /dev/tty
}

#
# @param lines
#
bsda:tty:Async.daemon_stdout() {
	/usr/bin/tput $($class.daemon_repeat $statusLines al) > /dev/tty
	eval "echo $1"
	$class.daemon_drawlines > /dev/tty
}

bsda:tty:Async.daemon() {
	$class.daemon_startup
	while $fifo.source read cmd; do
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
		exit
	;;
	*)
		echo "XXX $cmd"
	;;
	esac
	done
}

