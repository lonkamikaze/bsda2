test -n "$_bsda_messaging_" && return 0
readonly _bsda_messaging_=1

# Include framework for object oriented shell scripting.
. ${bsda_dir:-.}/bsda_obj.sh

#
# Offers classes to exchange character lines between processes.
#

#
# The following is a list of all classes and interfaces:
#
# | Class/Interface              | Description
# |------------------------------|-----------------------------------------
# | bsda:messaging:Listener      | Listener interface
# | bsda:messaging:Sender        | Sender interface
# | bsda:messaging:Messenger     | Messenger interface
# | bsda:messaging:Lock          | Read/Write file system locking class
# | bsda:messaging:BusListener   | Listener operating on a regular file
# | bsda:messaging:BusSender     | Sender operating on a regular file
# | bsda:messaging:BusMessenger  | Messenger operating on a regular file
# | bsda:messaging:FifoMessenger | Named pipe based based FIFO
#

#
# TABLES
#
# The following tables should help decide, which messenger type to use.
#
# Legend:
#
# | Type   | Communication Type
# |--------|--------------------------------------------------------------
# | Block. | Access blocks the process until the message is sent/received
# | Buff.  | Buffering
# | WL     | Writing Locks
# | RL     | Reading Locks
#
# Types:
#
# | Type | Description
# |------|---------------------------------------------------------
# | bus  | All messages are public to all bus participants
# | pipe | Named pipe, created with mkfifo(1), based communication
#		
#
# | Name          | Type | Block. | Buff. | WL | RL
# |---------------|------|--------|-------|----|----
# | _Listeners_   |      |        |       |    |
# | BusListener   | bus  | --     | --    | -- | -w
# | _Senders_     |      |        |       |    |
# | BusSender     | bus  | --     | --    | rw | --
# | _Messengers_  |      |        |       |    |
# | BusMessenger  | bus  | --     | --    | rw | -w
# | FifoMessenger | pipe | rw     | -w    | -- | --
#



#
# An interface for listeners.
#
bsda:obj:createInterface bsda:messaging:Listener \
	"
	# Receives data from a source.
	#
	# @param 1
	#	The received data.
	# @param 2
	#	The number of data lines received.
	#"\
	x:receive \
	"
	# Receives a single line of data.
	#
	# @param 1
	#	The received line.
	# @param 2
	#	The number or lines received (0 or 1).
	#"\
	x:receiveLine \

#
# An interface for senders.
#
bsda:obj:createInterface bsda:messaging:Sender \
	"
	# Sends data.
	#
	# @param 1
	#	The data to transmit.
	# @return 0
	#	Transmitting the data succeeded
	# @return 1
	#	Transmitting the data failed, the only permitted reason to
	#	fail sending is if it is required to read all present messages
	#	first.
	#"\
	x:send \

#
# An interface for messengers that allow bi-directional communication.
#
bsda:obj:createInterface bsda:messaging:Messenger \
	"
	# A Messenger has to provide all the methods expected from a Listener.
	#"\
	extends:bsda:messaging:Listener \
	"
	# A Messenger has to provide all the methods expected from a Sender.
	#"\
	extends:bsda:messaging:Sender \

#
# Instances of this class offer read and write locks to a file.
#
bsda:obj:createClass bsda:messaging:Lock  \
	w:private:lock \
		"The file to use for locking." \
	i:private:init \
		"The constructor." \
	c:private:clean \
		"The cleanup method." \
	x:public:lockRead \
		"Set this lock to forbid reading." \
	x:public:unlockRead \
		"Allow reading." \
	x:public:lockWrite \
		"Set this lock to forbid writing." \
	x:public:unlockWrite \
		"Allow writing."

#
# The constructor initializes attributes.
#
# @param 1
#	The file to lock.
# @return
#	1 if the lock cannot be acquired.
#
bsda:messaging:Lock.init() {
	local IFS
	# Make sure $bsda_obj_interpreter is split into several fields.
	IFS=' 	
'
	$this.setLock "$1"
	/usr/bin/lockf -ks "$1" $bsda_obj_interpreter -c "test -n \"\$(/bin/cat '$1' 2> /dev/null)\" || echo 0 > '$1'; /bin/chmod 0600 '$1'" || return 1
}

#
# Remove the lock file. If it is safe to do so.
#
bsda:messaging:Lock.clean() {
	local lock IFS
	IFS=' 	
'
	$this.getLock lock

	/usr/bin/lockf -k "$lock" $bsda_obj_interpreter -c "
		lock=\"\$(/bin/cat '$lock')\"
		test \${lock:-0} -eq 0 && rm '$lock'
	"
}

#
# Forbid reading from the file.
#
# To lock reading the lock value has to be 0 and will be set to -1.
# Reading may only be locked once .
#
bsda:messaging:Lock.lockRead() {
	local lock IFS
	IFS=' 	
'
	$this.getLock lock

	# run until the lock is acquired.
	while true; do
		# Get a file system lock on the lock file.
		/usr/bin/lockf -k "$lock" $bsda_obj_interpreter -c "
			lock=\"\$(/bin/cat '$lock')\"
			if [ \${lock:-0} -eq 0 ]; then
				echo -1 > '$lock'
				exit 0
			fi
			exit 1
		" && return 0
		sleep 0.01
	done
}

#
# Allow reading.
#
# Set the lock value back from -1 to 0.
#
# This does not check whether the lock was actually acquired, this simply
# is assumed.
#
bsda:messaging:Lock.unlockRead() {
	local lock IFS
	IFS=' 	
'
	$this.getLock lock

	# Get a file system lock on the lock file.
	/usr/bin/lockf -k "$lock" $bsda_obj_interpreter -c "echo 0 > '$lock'"
}

#
# Forbid writing to the file.
#
# To lock writing the lock value has to be 0 or greater and will be increased.
# This means that several processes at once may forbid writing (in order to
# read from the file) and only when all of these locks are undone, writing
# is possible, again.
#
bsda:messaging:Lock.lockWrite() {
	local lock IFS
	IFS=' 	
'
	$this.getLock lock
	locked=

	# run until the lock is acquired.
	while true; do
		# Get a file system lock on the lock file.
		/usr/bin/lockf -k "$lock" $bsda_obj_interpreter -c "
			lock=\"\$(/bin/cat '$lock')\"
			if [ \${lock:-0} -ge 0 ]; then
				echo \$((lock + 1)) > '$lock'
				exit 0
			fi
			exit 1
		" && return 0
		sleep 0.01
	done
}

#
# Allow writing to the file.
#
# Undo the lock value increment. If all of these have been undone, acquiring
# a lock for writing becomes possible again.
#
# This does not check whether the lock was actually acquired, this simply
# is assumed.
#
bsda:messaging:Lock.unlockWrite() {
	local lock IFS
	IFS=' 	
'
	$this.getLock lock

	# Get a file system lock on the lock file.
	/usr/bin/lockf -k "$lock" $bsda_obj_interpreter -c "echo \$((\$(/bin/cat '$lock') - 1)) > '$lock'"
}


#
# A listener on a file system message queue for read only access.
#
bsda:obj:createClass bsda:messaging:BusListener \
	implements:bsda:messaging:Listener \
	r:private:lock \
		"A Lock instance." \
	r:private:queue \
		"The queue file." \
	r:private:position \
		"The line number of the last received message." \
	i:private:init \
		"The constructor." \
	c:private:clean \
		"The destructor." \

#
# The constructor checks whether the message queue is available.
#
# @param 1
#	The file name of the message queue.
# @return
#	0 if everything goes fine
#	1 if creating a locking object fails
#
bsda:messaging:BusListener.init() {
	/usr/bin/lockf -ks "$1" /bin/chmod 0600 "$1" || return 1
	if ! bsda:messaging:Lock ${this}lock "$1.lock"; then
		/bin/rm "$1"
		return 1
	fi
	setvar ${this}queue "$1"
	setvar ${this}position 0
}

#
# The destructor deletes the queue and the lock.
#
# @param 1
#	If set the queue is deleted.
#
bsda:messaging:BusListener.clean() {
	local lock queue
	$this.getLock lock
	$this.getQueue queue

	$lock.delete
	test -n "$1" && rm "$queue"
	return 0
}

#
# Returns all unread lines from the message queue.
#
# @param 1
#	The name of the variable to store the received lines in.
# @param 2
#	The variable to store number of lines received in.
#
bsda:messaging:BusListener.receive() {
	local IFS position queue result lines lock
	IFS='
'

	$this.getLock lock
	$this.getPosition position
	$this.getQueue queue

	# Forbid writing to the file.
	$lock.lockWrite

	# Read and append an empty line saving postfix.
	result="$(
		/usr/bin/awk "NR > $position END {print \"EOF\"}" "$queue"
	)"

	# Permit writing to the file.
	$lock.unlockWrite

	# Get the mumber lines read. Because wc -l never returns 0, the
	# postfix helps us distuinguish between 1 and 0 lines.
	lines=$(($(echo "$result" | /usr/bin/wc -l) - 1))

	# Update position.
	setvar ${this}position $(($position + $lines))

	# Remove postfix.
	if [ $lines -gt 0 ]; then
		result="${result%${IFS}EOF}"
	else
		result=
	fi

	# Return the resulting lines.
	$caller.setvar "$1" "$result"
	$caller.setvar "$2" "$lines"
}

#
# Returns a single line from the message queue.
#
# @param 1
#	The name of the variable to store the received line in.
# @param 2
#	The variable to store number of lines received in.
#
bsda:messaging:BusListener.receiveLine() {
	local IFS position queue result lines lock
	IFS='
'

	$this.getLock lock
	$this.getPosition position
	$this.getQueue queue

	# Forbid writing to the file.
	$lock.lockWrite

	# Read a line and append an empty line saving postfix.
	result="$(
		/usr/bin/awk "NR == $position + 1 END {print \"EOF\"}" "$queue"
	)"

	# Permit writing to the file.
	$lock.unlockWrite

	# Get the mumber lines read. Because wc -l never returns 0, the
	# postfix helps us distuinguish between 1 and 0 lines.
	lines=$(($(echo "$result" | /usr/bin/wc -l) - 1))

	# Update position.
	setvar ${this}position $(($position + $lines))

	# Remove postfix.
	if [ $lines -gt 0 ]; then
		result="${result%${IFS}EOF}"
	else
		result=
	fi

	# Return the resulting line.
	$caller.setvar "$1" "$result"
	$caller.setvar "$2" "$lines"
}



#
# A bus sender class.
#
bsda:obj:createClass bsda:messaging:BusSender \
	implements:bsda:messaging:Sender \
	r:private:lock \
		"A Lock instance." \
	r:private:queue \
		"The queue file." \
	i:private:init \
		"The constructor." \
	c:private:clean \
		"The destructor." \

#
# The constructor checks whether the message queue is available.
#
# @param 1
#	The file name of the message queue.
# @return
#	0 if everything goes fine
#	1 if creating a locking object fails
#
bsda:messaging:BusSender.init() {
	/usr/bin/lockf -ks "$1" /bin/chmod 0600 "$1" || return 1
	if ! bsda:messaging:Lock ${this}lock "$1.lock"; then
		/bin/rm "$1"
		return 1
	fi
	setvar ${this}queue "$1"
}

#
# Borrow the destructor from the listener.
#
bsda:messaging:BusSender.clean() {
	bsda:messaging:BusListener.clean "$@"
}

#
# Sends a message.
#
# @param 1
#	The message to send.
#
bsda:messaging:BusSender.send() {
	local queue result lock
	$this.getLock lock
	$this.getQueue queue

	# Forbid reading.
	$lock.lockRead

	# Write the data.
	echo "$1" >> "$queue"

	# Permit reading.
	$lock.unlockRead
}


#
# A synchronous, file system based message queue access class. This can be used
# for many to many communication. It is still safe to use this after a fork.
# However the messenger object should not be synchronized between forked
# processes to preserve internal states.
#
# Because it is a synchronous message queue, receive() will always return
# all queued up message lines and send() will only work if there is no
# unread data left in the queue.
#
bsda:obj:createClass bsda:messaging:BusMessenger \
	implements:bsda:messaging:Messenger \
	extends:bsda:messaging:BusListener \


#
# Sends a message, unless there are unread messages in the queue.
#
# This means it might fail, in that case receive() has to be called before
# send() has a chance to work. There is no command that does send and
# receive at once, because it might be important that all receive data
# is processed in order to create a correct message.
#
# @param 1
#	The message to send.
# @return
#	0 if the message was sent
#	1 if the queue contains unreceived messages.
#
bsda:messaging:BusMessenger.send() {
	local position queue result lock

	$this.getLock lock
	$this.getPosition position
	$this.getQueue queue

	# Forbid reading.
	$lock.lockRead

	# Check whether this process is up to date. I.e. there are no unread
	# messages in the queue.
	if [ $(($(/usr/bin/wc -l < "$queue") - $position)) -eq 0 ]; then
		# This process is up to date. Write the data.
		echo "$1" >> "$queue"

		# Permit reading.
		$lock.unlockRead

		# Update the queue position, no need to read our own message.
		setvar ${this}position $(($position + $(echo "$1" | wc -l)))
		return 0
	else
		# Sending has failed, because we are not in sync with the
		# queue.

		# Permit reading.
		$lock.unlockRead
		return 1
	fi
	
}


#
# Creates a named pipe based messenger class.
#
# When multiple processes read from the FIFO, the recipient is randomly
# determined by the kernel.
#
# This messenger is suitable for polling free communication through the
# receiveLine() method, due to its blocking nature.
#
bsda:obj:createClass bsda:messaging:FifoMessenger \
	implements:bsda:messaging:Messenger \
	r:private:desc  "The I/O file descriptor number" \
	i:private:init  "Sets up the named pipe" \
	c:private:clean "Releases the file descriptor"

#
# Creates a FIFO messenger based on a named pipe.
#
# The file system node is immediately deleted after a file descriptor
# has been opened.
#
bsda:messaging:FifoMessenger.init() {
	local fifo desc
	# Create a named pipe
	fifo="$(/usr/bin/mktemp -ut $this)" || return
	/usr/bin/mkfifo "$fifo" || return
	# Open a file descriptor
	bsda:obj:getDesc desc || return
	eval "exec $desc<> \"\$fifo\""
	setvar ${this}desc "$desc"
	# Remove file system node for the named pipe
	/bin/rm "$fifo"
}

#
# Closes the file descriptor.
#
bsda:messaging:FifoMessenger.clean() {
	local desc
	$this.getDesc desc
	if [ -n "$desc" ]; then
		# Close the file descriptor
		eval "exec $desc<&-"
		eval "exec $desc>&-"
		bsda:obj:releaseDesc $desc
	fi
}

#
# This sends data.
#
# It blocks if the pipe buffer is full.
#
# @param 1
#	The message to send
#
bsda:messaging:FifoMessenger.send() {
	eval "echo \"\$1\" >&$($this.getDesc)"
}

#
# Gets a line from the FIFO.
#
# This blocks until a line is available.
#
# @param &1
#	Returns the received line
#
bsda:messaging:FifoMessenger.receiveLine() {
	local IFS line
	IFS='
'
	eval "read -r line <&$($this.getDesc)"
	$caller.setvar $1 "$line"
}

#
# Get all currently available data from the FIFO.
#
# Non-blocking.
#
# @param &1
#	Returns the received lines
# @param &2
#	Returns the number of lines
#
bsda:messaging:FifoMessenger.receive() {
	local IFS desc line lines count
	IFS='
'
	$this.getDesc desc
	lines=
	count=0
	while eval "read -rt0 line <&$desc"; do
		lines="$lines$line$IFS"
		count=$((count + 1))
	done
	$caller.setvar $1 "$lines"
	$caller.setvar $2 "$count"
}

