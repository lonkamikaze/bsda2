. ../src/bsda_test.sh
. ../src/bsda_obj.sh

# Evil IFS, to make sure everything is IFS safe. Using _ in IFS means
# every object reference needs to be quoted, which is annoying, but
# at least the backend should support this.
IFS=':._'

# Try setvar/getvar
setvar x 1337 && test "$x" = 1337
getvar y x && test "$y" = "$x"

# Calling bsda:obj:createClass() without arguments
! error=$(bsda:obj:createClass 2>&1)
bsda:test:match "bsda:obj:createClass: ERROR: *" "$error"

# Checking class creation
bsda:obj:createClass Foo
Foo.getMethods | grep -qFx public:delete
Foo.getMethods | grep -qFx public:dump
Foo.getMethods | grep -qFx public:copy
Foo.getMethods | grep -qFx public:serialise

# Checking implicit removal of copy and serialise for classes with
# a cleanup method
bsda:obj:createClass Bar c:clean
Bar.getMethods | grep -qFx public:delete
Bar.getMethods | grep -qFx public:dump
! Bar.getMethods | grep -qFx public:copy
! Bar.getMethods | grep -qFx public:serialise

# Create an instance
Foo foo

# Test empty obj dump format
dump=$("$foo".dump)
bsda:test:match 'Foo@* {}' "$dump"

# Test deleting
"$foo".delete
! error=$("$foo".delete 2>&1)
bsda:test:match "* not found" "$error"

# Test setters'n'getters
bsda:obj:createClass Baz w:value
Baz.getMethods | grep -qFx public:getValue
Baz.getMethods | grep -qFx public:setValue
Baz baz
"$baz".getValue x && test -z "$x"
"$baz".setValue 13
"$baz".getValue x && test "$x" = 13
"$baz".delete
# Test private/public
bsda:obj:createClass Baz w:private:value
Baz.getMethods | grep -qFx private:getValue
Baz.getMethods | grep -qFx private:setValue
# Use x: redeclaration
bsda:obj:createClass Baz \
	w:private:value x:public:getValue
Baz.getMethods | grep -qFx public:getValue
Baz.getMethods | grep -qFx private:setValue
bsda:obj:createClass Baz \
	x:public:getValue w:private:value
Baz.getMethods | grep -qFx public:getValue
Baz.getMethods | grep -qFx private:setValue
bsda:obj:createClass Baz \
	w:private:value x:getValue
Baz.getMethods | grep -qFx public:getValue
Baz.getMethods | grep -qFx private:setValue
# Use r: redecleration
bsda:obj:createClass Baz \
	w:private:value r:public:value
Baz.getMethods | grep -qFx public:getValue
Baz.getMethods | grep -qFx private:setValue
bsda:obj:createClass Baz \
	r:public:value w:private:value
Baz.getMethods | grep -qFx public:getValue
Baz.getMethods | grep -qFx private:setValue
bsda:obj:createClass Baz \
	w:private:value r:value
Baz.getMethods | grep -qFx public:getValue
Baz.getMethods | grep -qFx private:setValue

# Test private
Baz baz
! error=$("$baz".setValue 42 2>&1 )
bsda:test:match "Baz.setValue:*access*private*" "$error"
# Fake private
class=Baz
"$baz".setValue 42
unset class
"$baz".getValue x && test "$x" = 42

# Test copy
"$baz".copy baz1
"$baz1".getValue x && test "$x" = 42
"$baz1".delete
# Test serialise
"$baz".serialise serialised
x=0
getvar x "${baz}"value && test "$x" = 42
"$baz".delete
getvar x "${baz}"value && test -z "$x"
! error=$($baz.getValue x 2>&1 )
bsda:test:match "* not found" "$error"
bsda:obj:deserialise baz "$serialised"
x=0
"$baz".getValue x && test "$x" = 42
# Test dump format
"$baz".dump dump
bsda:test:match "Baz@* {\n  value='42'\n}" "$dump"

# Test methods
bsda:obj:createClass Boom x:foo
Boom.foo() { call="Boom.foo"; }
Boom boom
call=
"$boom".foo && test "$call" = "Boom.foo"
# Test $caller.setvar
Boom.foo() { "$caller".setvar "$1" "Boom.foo"; }
call=
"$boom".foo call && test "$call" = "Boom.foo"
call=$("$boom".foo) && test "$call" = "Boom.foo"
# Test recursion using fibonacci function
Boom.foo() {
	if [ $2 -le 2 ]; then
		"$caller".setvar "$1" 1
		return
	fi
	local a b
	"$this".foo a $(($2 - 1))
	"$this".foo b $(($2 - 2))
	"$caller".setvar "$1" $((a + b))
}
"$boom".foo x 7
test "$x" = 13

# Test initialiser/finaliser
bsda:obj:createClass Black i:private:init c:private:clean
Black.init() { call="Black.init"; }
Black.clean() { call="Black.clean"; }
call=
Black black
test "$call" = "Black.init"
"$black".delete
test "$call" = "Black.clean"

# Test $caller.delete
bsda:obj:createClass White x:run
call=
White.run() {
	local black
	Black black
	"$caller".delete "$black"
	test "$call" = "Black.init"
}
White white
"$white".run
test "$call" = "Black.clean"

# Test double initialiser function
! error=$(bsda:obj:createClass Bam i:foo i:bar 2>&1 )
bsda:test:match "bsda:obj:createClass: ERROR: *init*" "$error"
# Test double cleanup function
! error=$(bsda:obj:createClass Bam c:foo c:bar 2>&1 )
bsda:test:match "bsda:obj:createClass: ERROR: *cleanup*" "$error"

# Test delete thoroughly
bsda:obj:createClass Bob \
	r:private:rval \
	w:private:wval \
	x:private:func \
	i:private:init
Bob.init() {
	setvar "${this}"rval _rval_
	setvar "${this}"wval _wval_
}
# Test if everything got setup properly
Bob bob
bsda:test:isFunction "$bob".getRval
bsda:test:isFunction "$bob".setWval
bsda:test:isFunction "$bob".getWval
bsda:test:isFunction "$bob".func
bsda:test:isFunction "$bob".init
bsda:test:isFunction "$bob".copy
bsda:test:isFunction "$bob".dump
bsda:test:isFunction "$bob".serialise
bsda:test:isFunction "$bob".delete
getvar val "${bob}"rval && test "$val" = _rval_
getvar val "${bob}"wval && test "$val" = _wval_
# Test if everything gets removed properly
"$bob".delete
bsda:test:isNone "$bob".getRval
bsda:test:isNone "$bob".setWval
bsda:test:isNone "$bob".getWval
bsda:test:isNone "$bob".func
bsda:test:isNone "$bob".init
bsda:test:isNone "$bob".copy
bsda:test:isNone "$bob".dump
bsda:test:isNone "$bob".serialise
bsda:test:isNone "$bob".delete
! bsda:test:isSet "${bob}"rval
! bsda:test:isSet "${bob}"wval

# Test aggregation
bsda:obj:createClass A
bsda:obj:createClass B a:a=A i:private:init
bsda:obj:createClass C a:b=B a:a=A i:private:init
B.init() {
	A "${this}"a
}
C.init() {
	B "${this}"b
	A "${this}"a
}
# Create aggregation
C c
# Check structure
"$c".dump dump
bsda:test:match "C@*_0_ {\n  b=B@*_0_ {\n    a=A@*_0_ {}\n  }\n  a=A@*_1_ {}\n}" "$dump"
bsda:test:isFunction "$c".serialise
bsda:test:isFunction "$c".copy
# Copy and check copy
"$c".copy c1
"$c1".dump dump1
bsda:test:match "C@*_1_ {\n  b=B@*_1_ {\n    a=A@*_2_ {}\n  }\n  a=A@*_3_ {}\n}" "$dump1"
"$c1".delete
# Check recursive delete
"$c".b cb
"$c".a ca
"$cb".a cba
"$c".delete
! bsda:test:isSet "${c}"b
! bsda:test:isSet "${c}"a
! bsda:test:isSet "${cb}"a
bsda:test:isNone "$c".b
bsda:test:isNone "$c".a
bsda:test:isNone "$c".delete
bsda:test:isNone "$cb".a
bsda:test:isNone "$cb".delete
bsda:test:isNone "$cba".delete
# Check aggregation without type
bsda:obj:createClass D a:foo
D d
bsda:test:isNone "$d".serialise
bsda:test:isNone "$d".copy
"$d".delete
# Check aggregation with non copyable type
bsda:obj:createClass E c:private:clean
bsda:obj:createClass F a:a=A a:e=E
F f
bsda:test:isNone "$f".copy
bsda:test:isNone "$f".serialise
"$f".delete

# Test stack unwinding
bsda:obj:createClass SUa c:private:clean
SUa.clean() { echo A; }
bsda:obj:createClass SUb c:private:clean
SUb.clean() { echo B; }
bsda:obj:createClass SUc c:private:clean
SUc.clean() { echo C; }
bsda:obj:createClass SU \
	i:private:init \
	x:private:run
SU.init() {
	local obj
	SUa obj
	"$caller".delete "$obj"
	"$this".run
}
SU.run() {
	local obj
	SUb obj
	"$caller".delete "$obj"
	SUc obj
	"$caller".delete "$obj"
}
unwind="$(SU obj)"
test $'C\nB\nA' = "$unwind"

# Test terminal stack unwinding
SU.run() {
	local obj
	SUb obj
	"$caller".delete "$obj"
	SUc obj
	"$caller".delete "$obj"
	exit
}
unwind="$(bsda:obj:fork; SU obj)"
test $'C\nB\nA' = "$unwind"

# Test GC
bsda:obj:createClass GCa c:private:clean
GCa.clean() { echo GCa; }
bsda:obj:createClass GC \
	a:private:a=GCa \
	i:private:init \
	c:private:clean
GC.init() {
	local obj
	GCa ${this}a
	SU obj
	$caller.delete $obj
}
GC.clean() { echo GC; }
harvest="$(bsda:obj:fork; GC obj)"
test $'C\nB\nA\nGC\nGCa' = "$harvest"

# Test GC with unimplemented cleanup method
warn=$( (bsda:obj:fork;Bar bar) 2>&1 )
bsda:test:match "* not found\nbsda:obj:exit: WARNING: *" "$warn"
