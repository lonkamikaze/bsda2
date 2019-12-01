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
# output (sink) or input (source) is redirected through the named pipe:
#
#	bsda:fifo:Fifo fifo
#	$fifo.sink echo "This is my line" &
#	$fifo.source read -r line
#	echo "$line"
#
# The send() and recv() methods can be used to provide string argument
# access:
#
#      bsda:fifo:Fifo fifo
#      $fifo.send "This is my line" &
#      $fifo.recv line
#      echo "$line"
#
# The recv() function provides line wise access, multiple arguments
# can be provided to split a line into columns divided by the characters
# in IFS (see `read -r`).
#
# The send() function merges multiple arguments using `"$*"`, i.e.
# arguments are concatenated using the first character in IFS.
#
# Internally a set of named pipes is created one for I/O (fifo.pipe)
# and three for locking (send.lock, recv.lock and wait.lock).
#
# All locks initially block on read, locks can be freed by writing
# a newline character into the respective named pipe, allowing a single
# process' read from the lock to complete.
# The send.lock and recv.lock locks are initially freed by a guard
# processes. The guard process in turn waits for wait.lock to be
# freed. This is performed by the host process when the bsda:fifo:Fifo
# instance is deleted, causing the guard process to destroy the named
# pipe set and terminate.
#
bsda:obj:createClass bsda:fifo:Fifo \
	r:private:loc   "The named pipe file system location" \
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
	local loc
	# Create a named pipe location
	setvar ${this}loc "$(/usr/bin/mktemp -dt bsda:fifo)" || return $?
	$this.getLoc loc

	# Create the named pipes for I/O, and read/write locking
	/usr/bin/mkfifo -m 0600 "${loc}/fifo.pipe" \
	                        "${loc}/recv.lock" \
	                        "${loc}/send.lock" \
	                        "${loc}/wait.lock" || return $?

	# Open the pipes in a subprocess to make them non-blocking
	(
		# Ignore signals
		trap '' INT HUP TERM;
		# Make the pipes non-blocking
		exec 3<> "${loc}/fifo.pipe"
		exec 4<> "${loc}/recv.lock"
		exec 5<> "${loc}/send.lock"
		# Release the read/write locks
		echo >&4
		echo >&5
		# Acquire the wait lock to die
		read -r tmp < "${loc}/wait.lock"
		/bin/rm "${loc}/fifo.pipe" \
		        "${loc}/recv.lock" \
		        "${loc}/send.lock" \
		        "${loc}/wait.lock"
		/bin/rmdir "$loc"
	) &

	$this.send
	$this.recv
	$this.sink
	$this.source
}

#
# Write the given arguments to the FIFO.
#
# @param *
#	All arguments are written to the FIFO
# @param IFS
#	The first character of IFS is used to concatenate arguments
# @note
#	Usable after the first call, which is performed by the initialiser
#
bsda:fifo:Fifo.send() {
	local loc
	$this.getLoc loc
	eval "$this.send() {
		local bsda_fifo_Fifo_lock
		read -r bsda_fifo_Fifo_lock < ${loc}/send.lock
		echo \"\$*\" >> ${loc}/fifo.pipe
		echo >> ${loc}/send.lock
	}"
}

#
# Read one line from the FIFO.
#
# @param &@
#	The line is split into fields (see read -r)
# @param IFS
#	List of field separators
# @note
#	Usable after the first call, which is performed by the initialiser
#
bsda:fifo:Fifo.recv() {
	local loc
	$this.getLoc loc
	eval "$this.recv() {
		local bsda_fifo_Fifo_lock
		read -r bsda_fifo_Fifo_lock < ${loc}/recv.lock
		read -r \"\$@\" < ${loc}/fifo.pipe
		echo >> ${loc}/recv.lock
	}"
}

#
# Write the output of the given command to the FIFO.
#
# A call to this method is equivalent to using `eval` with the
# output redirected to the FIFO.
#
# @param @
#	The `eval` arguments
# @return
#	The return value of the executed command
# @note
#	Usable after the first call, which is performed by the initialiser
#
bsda:fifo:Fifo.sink() {
	local loc
	$this.getLoc loc
	eval "$this.sink() {
		local bsda_fifo_Fifo_lock bsda_fifo_Fifo_ret
		read -r bsda_fifo_Fifo_lock < ${loc}/send.lock
		eval \"\$@\" >> ${loc}/fifo.pipe
		bsda_fifo_Fifo_ret=\$?
		echo >> ${loc}/send.lock
		return \$bsda_fifo_Fifo_ret
	}"
}

#
# Read input from the FIFO.
#
# A call to this method is equivalent to using `eval` with the input
# connected to the FIFO.
#
# @param @
#	The `eval` arguments
# @return
#	The return value of the executed command
# @note
#	Usable after the first call, which is performed by the initialiser
#
bsda:fifo:Fifo.source() {
	local loc
	$this.getLoc loc
	eval "$this.source() {
		local bsda_fifo_Fifo_lock bsda_fifo_Fifo_ret
		read -r bsda_fifo_Fifo_lock < ${loc}/recv.lock
		eval \"\$@\" < ${loc}/fifo.pipe
		bsda_fifo_Fifo_ret=\$?
		echo >> ${loc}/recv.lock
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
	local loc die
	$this.getLoc loc
	# Release the wait lock
	echo >> "${loc}/wait.lock"
}
