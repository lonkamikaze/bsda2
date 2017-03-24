. ../src/bsda_container.sh
. ../src/bsda_test.sh
. ../src/bsda_util.sh

NL='
'
# Comma separated fields
IFS=","

# Lambda, produce comma separated list of key→value pairs
lambda() {
	kvs="${kvs:+$kvs,}$(printf "%s→%s" "$@")"
}

# Create a memory dump
memdump0="$(true;set)"

#
# Check bsda:container:Array
#

# Create array
bsda:container:Array arr a b c d e
kvs=
$arr.foreach lambda
test "0→a,1→b,2→c,3→d,4→e" = "$kvs"

# Check item count
$arr.getCount val && test "$val" = 5
# Value retrieval
$arr.[ 3 ] val && test "$val" = d
# Value assignment
$arr.[ 3 ]= D
$arr.[ 3 ] val && test "$val" = D
# Pop/Push
$arr.pop val && test "$val" = e
$arr.getCount val && test "$val" = 4
$arr.push E
$arr.getCount val && test "$val" = 5
# Verify
kvs=
$arr.foreach lambda
test "0→a,1→b,2→c,3→D,4→E" = "$kvs"

# Copy
$arr.copy arr1
kvs=
$arr1.foreach lambda
test "0→a,1→b,2→c,3→D,4→E" = "$kvs"
# Check serialise/deserialise
$arr1.serialise arr1s
# Restore modified object from serialised string
$arr1.[ 9 ]= X
$arr1.getCount val && test "$val" = 10
bsda:obj:deserialise arr1 "$arr1s"
$arr1.getCount val && test "$val" = 5
kvs=
$arr1.foreach lambda
test "0→a,1→b,2→c,3→D,4→E" = "$kvs"
# Delete and restore
$arr1.delete
unset arr1
bsda:obj:deserialise arr1 "$arr1s"
kvs=
$arr1.foreach lambda
test "0→a,1→b,2→c,3→D,4→E" = "$kvs"
# Clean up
$arr1.delete
$arr.delete
unset arr1 arr1s arr kvs val

# Create a new memory dump
memdump1="$(unset memdump0;true;set)"

# Compare before and after memory dumps, the only thing allowed to have
# changed are object ID counters.
diff01="$(echo "$memdump1" | grep -vFx "$memdump0")"
bsda:test:xmatch "$diff01" all:any "$bsda_obj_frameworkPrefix*_nextId=[0-9]*"

#
# Check bsda:container:Map
#

# Create map
bsda:container:Map map A a B b C c D d E e
kvs=
$map.foreach lambda
bsda:util:join kvs "$NL" $kvs
bsda:test:xmatch "$kvs" all:once A→a B→b C→c D→d E→e

# Check item count
$map.getCount val && test "$val" = 5
# Value retrieval
$map.[ D ] val && test "$val" = d
# Value assignment
$map.[ D ]= D
$map.[ D ] val && test "$val" = D
# Value removal
$map.[ E ]x
$map.getCount val && test "$val" = 4
$map.[ E ] val && test -z "$val"
# Special character assignment
$map.[ '%$foo&&{' ]= '$bar}'
$map.getCount val && test "$val" = 5
$map.[ '%$foo&&{' ] val && test "$val" = '$bar}'
# Verify
kvs=
$map.foreach lambda
bsda:util:join kvs "$NL" $kvs
bsda:test:xmatch "$kvs" all:once A→a B→b C→c D→D '%$foo&&{→$bar}'

# Copy
$map.copy map1
kvs=
$map1.foreach lambda
bsda:util:join kvs "$NL" $kvs
bsda:test:xmatch "$kvs" all:once A→a B→b C→c D→D '%$foo&&{→$bar}'
# Check serialise/deserialise
$map1.serialise map1s
# Restore modified object from serialised string
$map1.[ Z ]= X
$map1.getCount val && test "$val" = 6
bsda:obj:deserialise map1 "$map1s"
$map1.getCount val && test "$val" = 5
kvs=
$map1.foreach lambda
bsda:util:join kvs "$NL" $kvs
bsda:test:xmatch "$kvs" all:once A→a B→b C→c D→D '%$foo&&{→$bar}'
# Delete and restore
$map1.delete
unset map1
bsda:obj:deserialise map1 "$map1s"
kvs=
$map1.foreach lambda
bsda:util:join kvs "$NL" $kvs
bsda:test:xmatch "$kvs" all:once A→a B→b C→c D→D '%$foo&&{→$bar}'
# Clean up
$map1.delete
$map.delete
unset map1 map1s map kvs val

# Create a new memory dump
memdump2="$(unset diff01 memdump0 memdump1;true;set)"

# Compare before and after memory dumps, the only thing allowed to have
# changed are object ID counters.
diff12="$(echo "$memdump2" | grep -vFx "$memdump1")"
bsda:test:xmatch "$diff12" all:any "$bsda_obj_frameworkPrefix*_nextId=[0-9]*"
