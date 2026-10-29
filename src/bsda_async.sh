test -n "$_bsda_async_" && return 0
readonly _bsda_async_=1

. ${bsda_dir:-.}/bsda_fifo.sh
. ${bsda_dir:-.}/bsda_err.sh

#
# Module error codes.
#
# | Error Code                 | Severity | Meaning                                      |
# |----------------------------|----------|----------------------------------------------|
# | E_BSDA_ASYNC_DESTNAME      | error    | The name of the destination class is missing |
# | E_BSDA_ASYNC_SOURCENAME    | error    | The name of the source class is missing      |
# | E_BSDA_ASYNC_SOURCEINVALID | error    | Error accessing the source class traits      |
# | E_BSDA_ASYNC_CLASSINST     | panic    | Failed to initialise wrapped class instance  |
# | E_BSDA_ASYNC_PIPEFAIL      | panic    | Failed to read from pipe                     |
#
bsda:err:createECs E_BSDA_ASYNC_DESTNAME      \
                   E_BSDA_ASYNC_SOURCENAME    \
                   E_BSDA_ASYNC_SOURCEINVALID \
                   E_BSDA_ASYNC_CLASSINST     \
                   E_BSDA_ASYNC_PIPEFAIL

#
# Creates an asynchronous dispatch variant of an existing class.
#
# Each instance lives in a separate process, connected via bsda:fifo:Fifo.
#
# Method calls are serialised and sent through the FIFO along with
# $IFS. A 0xff byte is used to separate arguments, it is neither a
# valid ascii nor utf-8 code.
#
# @param 1
#	The name of the asynchronous class to create
# @param 2
#	The name of the class to manage in the asynchronous context
# @return
#	Returns 0 on success or an error code value if an error is
#	raised
#
bsda:async:createClass() {
	local IFS dstClass srcClass methods
	IFS=$'\n'
	dstClass="$1"
	srcClass="$2"
	readonly dstClass srcClass
	if [ -z "$dstClass" ]; then
		module=bsda:async:createClass bsda:err:raise E_BSDA_ASYNC_DESTNAME \
			"No destination class name supplied!"
		return
	fi
	if [ -z "$srcClass" ]; then
		module=bsda:async:createClass bsda:err:raise E_BSDA_ASYNC_SOURCENAME \
			"No source class name supplied!"
		return
	fi
	if ! $srcClass.getMethods methods 2>&-; then
		module=bsda:async:createClass bsda:err:raise E_BSDA_ASYNC_SOURCEINVALID \
			"Invalid source class ${srcClass}!"
		return
	fi
	local method forward
	# Generate forwarding functions
	forward=
	for method in $methods; do
		case "$method" in
		public:copy | public:delete | public:dump)
			# ignore
		;;
		public:*)
			forward="${forward}x:${method}${IFS}"
			eval "$dstClass.${method#*:}() {
				eval \"\$this.${method#*:}() {
					bsda:async:call \$(\$this.bsda_async_Fifo) \$(\$this.getBsda_async_obj).${method#*:} \\\"\\\$@\\\"
				}\"
				\$this.${method#*:} \"\$@\"
			}"
		;;
		esac
	done
	bsda:obj:createClass $dstClass \
		a:private:bsda_async_Fifo=bsda:fifo:Fifo \
		r:private:bsda_async_pid \
		r:private:bsda_async_obj \
		i:private:bsda_async_init \
		c:private:bsda_async_free \
		$forward
	eval "
	$dstClass.bsda_async_init() {
		bsda:async:init $srcClass \"\$@\"
	}
	$dstClass.bsda_async_free() {
		bsda:async:free \"\$@\"
	}
	"
}

#
# Serialise and dispatch a call.
#
# @param 1
#	The bsda:fifo:Fifo instance to dispatch through
# @param 2
#	The call to execute in the asynchronous context
# @param @
#	Call arguments
#
bsda:async:call() {
	$1.send "IFS=\$'\377'; set -- \$(printf '$(shift; IFS=$'\377'; echo -n "$*" | bsda:obj:escape)'); IFS=\"\$(printf '$(echo -n "$IFS." | bsda:obj:escape)')\"; IFS=\"\${IFS%.}\"; \"\$@\""
}

#
# Construct an async class instance.
#
# @param @
#	Arguments are forwarded to the constructor of the managed class
# @retval 1
#	Construction failed
# @retval 0
#	The asynchronous context was successfully set up
#
bsda:async:init() {
	local fifo obj
	bsda:fifo:Fifo ${this}bsda_async_Fifo || return 1
	bsda:async:daemon "$@" &
	setvar ${this}bsda_async_pid $!
	$this.bsda_async_Fifo fifo
	$fifo.recv ${this}bsda_async_obj
	$this.getBsda_async_obj obj
	test -n "$obj"
}

#
# Harvest the asynchronous context.
#
bsda:async:free() {
	local pid fifo
	$this.getBsda_async_pid pid
	if [ -n "$pid" ]; then
		$this.bsda_async_Fifo fifo
		$fifo.send 'exit 0'
		wait "$pid"
	fi
}

#
# Setup an asynchronous context creating an instance of the managed
# class.
#
# This must be run in a separate context. It calls bsda:obj:fork().
#
# @param 1
#	The name of the managed class
# @param @
#	Constructor arguments for the managed class instance
#
bsda:async:daemon() {
	bsda:obj:fork
	local fifo objClass obj cmd retval
	trap '' HUP INT TERM
	$this.bsda_async_Fifo fifo
	objClass="$1"
	shift
	$objClass obj "$@"
	retval=$?
	if [ $retval -ne 0 ]; then
		module=bsda:async:daemon bsda:err:panic E_BSDA_ASYNC_CLASSINST \
			"Failed to instantiate async $class instance, constructor returned: $retval"
	fi

	# Send the object ID to the host process, there is a race
	# condition where the daemon receives the object ID instead
	# of the host process, this will simply resend in this case.
	eval "$obj() { $fifo.send $obj; }"
	$obj

	while true; do
		cmd=
		$fifo.recv cmd
		retval=$?
		if [ $retval -gt 128 ]; then
			# Retry read if interrupted by a signal
			continue
		elif [ $retval -ne 0 ]; then
			module=bsda:async:daemon bsda:err:panic E_BSDA_ASYNC_PIPEFAIL \
				"Read from pipe returned: $retval"
		fi
		eval "$cmd"
	done
}
