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
bsda:obj:createClass bsda:fifo:Fifo \
	r:private:desc  "The I/O file descriptor number" \
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
	local fifo desc
	# Create a named pipe
	fifo="$(/usr/bin/mktemp -ut $this)" || return
	bsda:obj:getDesc desc || return
	/usr/bin/mkfifo "$fifo" || return
	# Open a file descriptor
	eval "exec $desc<> '$fifo'"
	# Remove file system node for the named pipe
	/bin/rm "$fifo"
	setvar ${this}desc "$desc"
	# Create sink() and source() methods
	eval "
	$this.sink() {
		eval \"\$@\" >&$desc
	}
	$this.source() {
		eval \"\$@\" <&$desc
	}"
}

#
# Clean up behind the fifo.
#
# The destructor closes the file descriptor, releases it back into the
# pool of available descriptors and removes the sink() and source()
# methods.
#
bsda:fifo:Fifo.clean() {
	local desc
	$this.getDesc desc
	eval "exec $desc<&-"
	eval "exec $desc>&-"
	bsda:obj:releaseDesc $desc
}

