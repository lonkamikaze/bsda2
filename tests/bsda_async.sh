. ../src/bsda_async.sh
. ../src/bsda_fifo.sh
. ../src/bsda_test.sh

# Create an asynchronous runner that outputs into a FIFO
bsda:obj:createClass Runner x:public:eval
bsda:async:createClass AsyncRunner Runner
bsda:fifo:Fifo fifo
eval "Runner.eval() {
	$fifo.sink \"\$@\"
}"

#
# Test both a synchronous and an asynchronous runner to verify the
# procedure for both cases.
#
prestate="$(x=0; set | grep -v _nextId=)"
Runner sync
AsyncRunner async

for run in $sync $async; do
	# Check dump of object
	$run.eval '$this.dump'
	$fifo.recv dump
	bsda:test:gmatch "Runner@${bsda_obj_frameworkPrefix}*_ {}" "$dump"

	# Check whether the object exist in this process
	$run.eval 'echo $this'
	$fifo.recv obj
	test -n "$obj"
	if [ $run = $sync ]; then
		type="$(type $obj.dump 2>&1)"
	fi
	if [ $run = $async ]; then
		! type="$(type $obj.dump 2>&1)"
	fi
	# Remove facility
	$run.delete
done

# Check for complete cleanup
unset sync async run dump obj type
poststate="$(unset prestate; x=0; set | grep -v _nextId=)"
test "$prestate" = "$poststate"
