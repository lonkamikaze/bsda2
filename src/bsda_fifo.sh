test -n "$_bsda_fifo_" && return 0
readonly _bsda_fifo_=1

. ${bsda_dir:-.}/bsda_obj.sh

#
# Offers a light weight mkfifo(1) wrapper to create and use named pipes.
#

#
# Provides a light weight wrapper around mkfifo(1).
#
# Creating this prior to forking opens a two-way communication pipe
# between processes.
#
# The send() and recv() methods can be used to provide string argument
# access:
#
#	bsda:fifo:Fifo fifo
#	$fifo.send "This is my line" &
#	$fifo.recv line
#	echo "$line"
#
# The recv() function provides line wise access, multiple arguments
# can be provided to split a line into columns divided by the characters
# in $IFS (see `read -r`).
#
# The send() function merges multiple arguments using `"$*"`, i.e.
# arguments are concatenated using the first character in $IFS.
#
# The sink() and source() methods are used like eval. The given command's
# output (sink) or input (source) is redirected through the named pipe.
#
# E.g.:
#
#	bsda:fifo:Fifo fifo
#	$fifo.sink echo "This is my line" &
#	$fifo.source read -r line
#	echo "$line"
#
# Note that this consumes three file descriptors out of the small pool
# of 7 available descriptors (this is a hard-coded limit in ASH).
# The second and third descriptor are used as a write and read lock
# facilities.
# The locking pipes are initialised with a single byte, which is consumed
# by sink() before writing to or by source() before reading from the
# messaging pipe.
# Any other process trying to write into or read from the messaging
# pipe is suspended until the concurrent sink() or source() method
# completes and puts a new byte into the locking pipe.
#
bsda:obj:createClass bsda:fifo:Fifo \
	r:private:desc  "The I/O file descriptor number" \
	r:private:wlock "The write lock file descriptor number" \
	r:private:rlock "The read lock file descriptor number" \
	i:private:init  "Sets up the named pipe" \
	c:private:clean "Releases the file descriptor" \
	x:public:send   "Send a string" \
	x:public:recv   "Receive a string" \
	x:public:sink   "Use like eval to send" \
	x:public:source "Use like eval to read"

#
# The constructor sets up two-way communication.
#
# It creates a named pipe, opens a file descriptor, unlinks the named
# pipe and creates low overhead source() and sink() methods.
#
bsda:fifo:Fifo.init() {
	local fifo desc wlock rlock
	# Create a named pipe
	fifo="$(/usr/bin/mktemp -ut $this)" || return $?
	bsda:obj:getDesc ${this}desc || return $?
	$this.getDesc desc
	/usr/bin/mkfifo -m 0600 "$fifo" || return $?
	# Open a file descriptor
	eval "exec $desc<> '$fifo'"
	# Remove file system node for the named pipe
	/bin/rm "$fifo"

	# Create a named pipe for the write lock
	bsda:obj:getDesc ${this}wlock || return $?
	$this.getWlock wlock
	/usr/bin/mkfifo -m 0600 "$fifo" || return $?
	# Open a file descriptor
	eval "exec $wlock<> '$fifo'"
	# Remove file system node for the named pipe
	/bin/rm "$fifo"
	# Release the lock for starters
	echo >&$wlock

	# Create a named pipe for the read lock
	bsda:obj:getDesc ${this}rlock || return $?
	$this.getRlock rlock
	/usr/bin/mkfifo -m 0600 "$fifo" || return $?
	# Open a file descriptor
	eval "exec $rlock<> '$fifo'"
	# Remove file system node for the named pipe
	/bin/rm "$fifo"
	# Release the lock for starters
	echo >&$rlock

	# Create sink() and source() methods
	eval "
	$this.send() {
		local bsda_fifo_Fifo_lock
		read -r bsda_fifo_Fifo_lock <&$wlock
		echo \"\$*\" >&$desc
		echo >&$wlock
	}
	$this.recv() {
		local bsda_fifo_Fifo_lock
		read -r bsda_fifo_Fifo_lock <&$rlock
		read -r \"\$@\" <&$desc
		echo >&$rlock
	}
	$this.sink() {
		local bsda_fifo_Fifo_lock bsda_fifo_Fifo_ret
		read -r bsda_fifo_Fifo_lock <&$wlock
		eval \"\$@\" >&$desc
		bsda_fifo_Fifo_ret=\$?
		echo >&$wlock
		return \$bsda_fifo_Fifo_ret
	}
	$this.source() {
		local bsda_fifo_Fifo_lock bsda_fifo_Fifo_ret
		read -r bsda_fifo_Fifo_lock <&$rlock
		eval \"\$@\" <&$desc
		bsda_fifo_Fifo_ret=\$?
		echo >&$rlock
		return \$bsda_fifo_Fifo_ret
	}"
}

#
# Clean up behind the fifo.
#
# The destructor closes the file descriptors and releases them back
# into the pool of available descriptors.
#
bsda:fifo:Fifo.clean() {
	local desc
	$this.getDesc desc
	eval "${desc:+exec $desc>&-}"
	bsda:obj:releaseDesc $desc
	$this.getWlock desc
	eval "${desc:+exec $desc>&-}"
	bsda:obj:releaseDesc $desc
	$this.getRlock desc
	eval "${desc:+exec $desc>&-}"
	bsda:obj:releaseDesc $desc
}
