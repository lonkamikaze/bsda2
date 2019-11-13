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
	bsda:obj:getDesc desc || return $?
	setvar ${this}desc "$desc"
	/usr/bin/mkfifo "$fifo" || return $?
	# Open a file descriptor
	eval "exec $desc<> '$fifo'"
	# Remove file system node for the named pipe
	/bin/rm "$fifo"

	# Create a named pipe for the write lock
	bsda:obj:getDesc wlock || return $?
	setvar ${this}wlock "$wlock"
	/usr/bin/mkfifo "$fifo" || return $?
	# Open a file descriptor
	eval "exec $wlock<> '$fifo'"
	# Remove file system node for the named pipe
	/bin/rm "$fifo"
	# Release the lock for starters
	echo >&$wlock

	# Create a named pipe for the read lock
	bsda:obj:getDesc rlock || return $?
	setvar ${this}rlock "$rlock"
	/usr/bin/mkfifo "$fifo" || return $?
	# Open a file descriptor
	eval "exec $rlock<> '$fifo'"
	# Remove file system node for the named pipe
	/bin/rm "$fifo"
	# Release the lock for starters
	echo >&$rlock

	# Create sink() and source() methods
	eval "
	$this.sink() {
		local bsda_fifo_Fifo_lock
		read -r bsda_fifo_Fifo_lock <&$wlock
		eval \"\$@\" >&$desc
		echo >&$wlock
	}
	$this.source() {
		local bsda_fifo_Fifo_lock
		read -r bsda_fifo_Fifo_lock <&$rlock
		eval \"\$@\" <&$desc
		echo >&$rlock
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
