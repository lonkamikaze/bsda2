. ../src/bsda_fifo.sh
. ../src/bsda_test.sh
. ../src/bsda_util.sh

NL=$'\n'

# Record number of file descriptors
IFS=,
bsda:util:count fdcount0 $bsda_obj_desc
# Create a Fifo instance
bsda:fifo:Fifo fifo
# Check if file descriptors were consumed
bsda:util:count fdcount1 $bsda_obj_desc
test $fdcount1 -le $fdcount0
# Fifos are not serialisable or copyable
bsda:test:isNone $fifo.serialise
bsda:test:isNone $fifo.copy
# Send something through the fifo
$fifo.sink echo foobar
$fifo.source read -r str
test "$str" = foobar
# Send a big thing many times in parallel
doc="$(cat ../ref/bsda_obj.md)$NL"
IFS="$NL"
threads=8
pids=
for i in $(jot $threads); do
	$fifo.sink 'echo -n "$doc"' &
	pids="${pids}$!${NL}"
done
for i in $(jot $threads); do
	recv=
	while [ "$recv" != "$doc" ]; do
		$fifo.source read -rt5 line
		recv="$recv$line$NL"
	done
done
wait $pids
# Clean up
$fifo.delete
IFS=,
bsda:util:count fdcount2 $bsda_obj_desc
test $fdcount2 -eq $fdcount0

# Creating fifos must eventually fail if file descriptors are consumed
if [ $((fdcount0)) -lt $((fdcount1)) ]; then
	fdcount_last=$fdcount0
	while bsda:fifo:Fifo fifo; do
		bsda:util:count fdcount $bsda_obj_desc
		test $fdcount -lt $fdcount_last
		fdcount_last=$fdcount
	done
fi
