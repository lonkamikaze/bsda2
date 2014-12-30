#
# Copyright (c) 2009, 2010, 2014
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
test -n "$bsda_messaging" && return 0
readonly bsda_messaging=1

# Include framework for object oriented shell scripting.
. ${bsda_dir:-.}/bsda_obj.sh

#
# Offers classes to exchange character lines between processes.
#

#
# The following is a list of all classes and interfaces:
#	bsda:messaging:Listener		Listener interface
#	bsda:messaging:Sender		Sender interface
#	bsda:messaging:Messenger	Messenger interface
#	bsda:messaging:Lock		Read/Write file system locking class
#	bsda:messaging:BusListener	Listener operating on a regular file
#	bsda:messaging:BusSender	Sender operating on a regular file
#	bsda:messaging:BusMessenger	Messenger operating on a regular file
#	bsda:messaging:PtpMessenger	Messenger for 1-1 process communication
#	bsda:messaging:FifoListener	Listener for a FIFO
#	bsda:messaging:FifoSender	Sender for a FIFO
#

#
# TABLES
#
# The following tables should help decide, which messenger type to use.
#
# Legend
#	Type	Communication Type
#	Block.	Read access blocks the process until a message is received
#	Buff.	Buffering
#	WL	Writing Locks
#	RL	Reading Locks
#
# Types
#	bus	Every participant can send and receive, every message is
#		available to every participant.
#	ptp	Point To Point communication, there are only two communication
#		partners, messages are only received by the partner
#	queue	Messages are kept in a queue, the first listener to read
#		gets the message. Queues may not be read buffered.
#		
#
# Listeners
#	Name			Type	Block.	Buff.	WL	RL
#	BusListener		bus	no	--	--	-w
#	FifoListener		ptp	no	r-	--	rw
#
# Senders
#	Name			Type	Block.	Buff.	WL	RL
#	BusSender		bus	-	--	rw	--
#	FifoSender		ptp	-	--	rw	--
#
# Messengers
#	Name			Type	Block.	Buff.	WL	RL
#	BusMessenger		bus	no	--	rw	-w
#	PtpMessenger		ptp	no	r-	r-	r-
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
# A raw sender class, .
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
# A synchronus, file system based message queue access class. This can be used
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
# A pair messenger allows 1-1 communication between a parent and child process.
#
# It is much faster than the BusMessenger, which has the benefit of
# allowing n-n communication.
#
# The PtpMessenger instance should be created prior to a fork and only used
# by the main process and a single forked process. It cannot be used for
# communication between several forked processes.
#
# Using this messenger requires appropriate use of the bsda:obj:fork()
# function.
#
bsda:obj:createClass bsda:messaging:PtpMessenger \
	implements:bsda:messaging:Messenger \
	r:private:pid \
		"The PID of the original process" \
	r:private:fifo \
		"The message FIFO file name." \
	w:private:buffer \
		"The message read buffer." \
	w:private:bufferLines \
		"The message read buffer length in lines." \
	i:private:init \
		"The constructor." \
	c:private:clean \
		"The destructor." \

#
# The constructor checks whether the message FIFO is available.
#
# It creates two files acting as non-blocking FIFOs for each process.
#
# @param 1
#	The file name prefix for the message FIFO.
# @return
#	0 if everything goes fine
#	1 if creating a locking object fails
#
bsda:messaging:PtpMessenger.init() {
	/usr/bin/lockf -ks "$1.master.fifo" /bin/chmod 0600 "$1.master.fifo" || return 1
	if ! /usr/bin/lockf -ks "$1.fork.fifo" /bin/chmod 0600 "$1.fork.fifo"; then
		/bin/rm "$1.master.fifo"
		return 1
	fi
	setvar ${this}fifo "$1"
	setvar ${this}pid "$bsda_obj_pid"
}

#
# The destructor deletes the FIFOs if requested.
#
# @param 1
#	If set the FIFOs are deleted.
#
bsda:messaging:PtpMessenger.clean() {
	local fifo
	$this.getFifo fifo

	test -n "$1" && /bin/rm "$fifo.master.fifo" "$fifo.fork.fifo"
	return 0
}

#
# Sends a message.
#
# @param 1
#	The message to send.
#
bsda:messaging:PtpMessenger.send() {
	local IFS fifo pid
	# Make sure $bsda_obj_interpreter is split into several fields.
	IFS=' 	
'

	$this.getFifo fifo
	$this.getPid pid

	# Check whether this is the master process or the fork.
	if [ $pid = $bsda_obj_pid ]; then
		# This is the master, send to the fork.
		fifo="$fifo.fork.fifo"
	else
		# This is the fork, send to the master.
		fifo="$fifo.master.fifo"
	fi

	echo "$1" | /usr/bin/lockf -ks "$fifo" $bsda_obj_interpreter -c "/bin/cat >> '$fifo'"
}

#
# Returns all unread lines from the message FIFO.
#
# @param 1
#	The name of the variable to store the received lines in.
# @param 2
#	The variable to store number of lines received in.
#
bsda:messaging:PtpMessenger.receive() {
	local IFS fifo pid output count buffer bufferLines

	$this.getFifo fifo
	$this.getPid pid

	# Check whether this is the master process or the fork.
	if [ $pid = $bsda_obj_pid ]; then
		# This is the master, read from the master FIFO.
		fifo="$fifo.master.fifo"
	else
		# This is the fork, read from the fork FIFO.
		fifo="$fifo.fork.fifo"
	fi

	# Make sure $bsda_obj_interpreter is split into several fields.
	IFS=' 	
'
 
	# Read and flush the FIFO
	output="$(/usr/bin/lockf -ks "$fifo" $bsda_obj_interpreter -c "
			/usr/bin/awk '1 END {print NR}' '$fifo'
			echo -n > '$fifo'
		"
	)"

	# Set IFS to line break.
	IFS='
'
	# Return the results.
	$this.getBuffer buffer
	$this.getBufferLines bufferLines
	count="${output##*$IFS}"
	output="${output%$count}"
	output="${output%$IFS}"
	$caller.setvar "$1" "$buffer${buffer:+${output:+$IFS}}$output"
	$caller.setvar "$2" $((bufferLines + count))
	unset ${this}buffer ${this}bufferLines
}

#
# Returns the first line from the message FIFO.
#
# @param 1
#	The name of the variable to store the received line in.
# @param 2
#	The variable to store number of lines received in.
#
bsda:messaging:PtpMessenger.receiveLine() {
	local IFS count buffer output

	IFS='
'

	# Update the read buffer if necessary.
	$this.getBufferLines count
	if [ $((count)) -eq 0 ]; then
		$this.receive ${this}buffer ${this}bufferLines
	fi

	# Get the output line from the buffer.
	$this.getBuffer buffer
	$this.getBufferLines count
	output="${buffer%%$IFS*}"

	# Return the output line.
	$caller.setvar "$1" "$output"
	$caller.setvar "$2" $((count >= 1))

	# Update the buffer.
	if [ "$buffer" == "${buffer#*$IFS}" ]; then
		buffer=
	fi
	$this.setBuffer "${buffer#*$IFS}"
	$this.setBufferLines $((count - (count >= 1) ))
}

#
# Instances of this class allow reading data from a FIFO.
#
# Only a single process should read from a FIFO.
#
bsda:obj:createClass bsda:messaging:FifoListener \
	implements:bsda:messaging:Listener \
	r:private:fifo \
		"The fifo file." \
	w:private:buffer \
		"The message read buffer." \
	w:private:bufferLines \
		"The message read buffer length in lines." \
	i:private:init \
		"The constructor creates the FIFO." \
	c:private:clean \
		"The destructor." \

#
# The constructor checks whether the FIFO can be locked.
#
# @param 1
#	The file name of the FIFO.
# @return 0
#	Locking the FIFO succeeded.
# @return 1
#	Locking the FIFO did not succeed.
#
bsda:messaging:FifoListener.init() {
	/usr/bin/lockf -ks "$1.fifo" /bin/chmod 0600 "$1.fifo" || return 1
	setvar ${this}fifo "$1.fifo"
}

#
# The destructor deletes the FIFO if requested.
#
bsda:messaging:FifoListener.clean() {
	local fifo
	$this.getFifo fifo

	/bin/rm "$fifo"
	return 0
}

#
# Returns all unread lines from the FIFO.
#
# @param 1
#	The name of the variable to store the received lines in.
# @param 2
#	The variable to store number of lines received in.
#
bsda:messaging:FifoListener.receive() {
	local IFS fifo output count buffer bufferLines

	$this.getFifo fifo

	# Make sure $bsda_obj_interpreter is split into several fields.
	IFS=' 	
'
 
	# Read and flush the FIFO
	output="$(/usr/bin/lockf -ks "$fifo" $bsda_obj_interpreter -c "
			/usr/bin/awk '1 END {print NR}' '$fifo'
			echo -n > '$fifo'
		"
	)"

	# Set IFS to line break.
	IFS='
'
	# Return the results.
	$this.getBuffer buffer
	$this.getBufferLines count
	$this.getBufferLines bufferLines
	count="${output##*$IFS}"
	output="${output%$count}"
	output="${output%$IFS}"
	$caller.setvar "$1" "$buffer${buffer:+${output:+$IFS}}$output"
	$caller.setvar "$2" $((bufferLines + count))
	unset ${this}buffer ${this}bufferLines
}

#
# Returns the first line from the message FIFO.
#
# @param 1
#	The name of the variable to store the received line in.
# @param 2
#	The variable to store number of lines received in.
#
bsda:messaging:FifoListener.receiveLine() {
	local IFS count buffer output

	IFS='
'

	# Update the read buffer if necessary.
	$this.getBufferLines count
	if [ $((count)) -eq 0 ]; then
		$this.receive ${this}buffer ${this}bufferLines
	fi

	# Get the output line from the buffer.
	$this.getBuffer buffer
	$this.getBufferLines count
	output="${buffer%%$IFS*}"

	# Return the output line.
	$caller.setvar "$1" "$output"
	$caller.setvar "$2" $((count >= 1))

	# Update the buffer.
	if [ "$buffer" == "${buffer#*$IFS}" ]; then
		buffer=
	fi
	$this.setBuffer "${buffer#*$IFS}"
	$this.setBufferLines $((count - (count >= 1) ))
}

#
# Instances of this class allow storing data in a FIFO.
#
# FIFOs are useful for n to 1 single direction communication (many senders, one
# receiver).
#
bsda:obj:createClass bsda:messaging:FifoSender \
	implements:bsda:messaging:Sender \
	r:private:fifo \
		"The fifo file." \
	i:private:init \
		"The constructor creates the FIFO."

#
# The constructor checks whether the FIFO can be locked.
#
# @param 1
#	The file name of the FIFO.
# @return 0
#	Locking the FIFO succeeded.
# @return 1
#	Locking the FIFO did not succeed.
#
bsda:messaging:FifoSender.init() {
	bsda:messaging:FifoListener.init "$@"
}

#
# Sends a message.
#
# @param 1
#	The message to send.
#
bsda:messaging:FifoSender.send() {
	local IFS fifo
	# Make sure $bsda_obj_interpreter is split into several fields.
	IFS=' 	
'
	$this.getFifo fifo
	echo "$1" | /usr/bin/lockf -ks "$fifo" $bsda_obj_interpreter -c "/bin/cat >> '$fifo'"
}

