. ../src/type.sh

#
# Check single type match functions
#

type:match:empty
type:match:empty ''
! type:match:empty 0
! type:match:empty foo

type:match:bool 1
type:match:bool 0
type:match:bool yes
type:match:bool yeS
type:match:bool no
type:match:bool nO
type:match:bool No
type:match:bool NO
type:match:bool True
type:match:bool truE
type:match:bool false
! type:match:bool 2
! type:match:bool foo
! type:match:bool

type:match:uint 0xaffe
type:match:uint 0xAFFE
type:match:uint 0Xaffe
type:match:uint 1337
type:match:uint 0755
type:match:uint 0
! type:match:uint 0x
! type:match:uint +1
! type:match:uint -1
! type:match:uint
! type:match:uint yes
! type:match:uint FALSE

type:match:int 0xaffe
type:match:int 0xAFFE
type:match:int 0Xaffe
type:match:int 1337
type:match:int 0755
type:match:int 0
! type:match:int 0x
! type:match:int
! type:match:int yes
! type:match:int FALSE

type:match:int +0xaffe
type:match:int +0xAFFE
type:match:int +0Xaffe
type:match:int +1337
type:match:int +0755
type:match:int +0
! type:match:int +0x
! type:match:int
! type:match:int +
! type:match:int +yes
! type:match:int +FALSE

type:match:int -0xaffe
type:match:int -0xAFFE
type:match:int -0Xaffe
type:match:int -1337
type:match:int -0755
type:match:int -0
! type:match:int -0x
! type:match:int
! type:match:int -
! type:match:int -yes
! type:match:int -FALSE

#
# Check multiple type match functions
#

# Single type matches
type:match empty
! type:match empty foo
type:match bool yes
! type:match bool 2
type:match uint 0xAFFE
! type:match uint -1
type:match int +0755
! type:match int 0x

# Multiple type matches
type:match bool,empty
! type:match bool,empty foo
type:match empty,bool
! type:match empty,bool foo
type:match bool,empty,int -0755
! type:match bool,empty,uint -0755

#
# Check type:cast[int] functions
#

x=nope
type:cast[int]:empty x
test "$x" = 0
x=nope
type:cast[int]:empty x ''
test "$x" = 0
x=nope
! type:cast[int]:empty x 0
test "$x" = nope
! type:cast[int]:empty x foo
test "$x" = nope

type:cast[int]:bool x 1
test "$x" = 1
type:cast[int]:bool x 0
test "$x" = 0
type:cast[int]:bool x yes
test "$x" = 1
x=nope
type:cast[int]:bool x yeS
test "$x" = 1
x=nope
type:cast[int]:bool x no
test "$x" = 0
x=nope
type:cast[int]:bool x nO
test "$x" = 0
x=nope
type:cast[int]:bool x No
test "$x" = 0
x=nope
type:cast[int]:bool x NO
test "$x" = 0
x=nope
type:cast[int]:bool x True
test "$x" = 1
x=nope
type:cast[int]:bool x truE
test "$x" = 1
x=nope
type:cast[int]:bool x false
test "$x" = 0
x=nope
! type:cast[int]:bool x 2
test "$x" = nope
! type:cast[int]:bool x foo
test "$x" = nope
! type:cast[int]:bool x
test "$x" = nope

x=nope
type:cast[int]:uint x 0xaffe
test "$x" = 45054
x=nope
type:cast[int]:uint x 0xAFFE
test "$x" = 45054
x=nope
type:cast[int]:uint x 0Xaffe
test "$x" = 45054
type:cast[int]:uint x 1337
test "$x" = 1337
type:cast[int]:uint x 0755
test "$x" = 493
type:cast[int]:uint x 0
test "$x" = 0
x=nope
! type:cast[int]:uint x 0x
test "$x" = nope
! type:cast[int]:uint x +1
test "$x" = nope
! type:cast[int]:uint x -1
test "$x" = nope
! type:cast[int]:uint x
test "$x" = nope
! type:cast[int]:uint x yes
test "$x" = nope
! type:cast[int]:uint x FALSE
test "$x" = nope

x=nope
type:cast[int]:int x 0xaffe
test "$x" = 45054
x=nope
type:cast[int]:int x 0xAFFE
test "$x" = 45054
x=nope
type:cast[int]:int x 0Xaffe
test "$x" = 45054
type:cast[int]:int x 1337
test "$x" = 1337
type:cast[int]:int x 0755
test "$x" = 493
type:cast[int]:int x 0
test "$x" = 0
x=nope
! type:cast[int]:int x 0x
test "$x" = nope
! type:cast[int]:int x
test "$x" = nope
! type:cast[int]:int x yes
test "$x" = nope
! type:cast[int]:int x FALSE
test "$x" = nope

type:cast[int]:int x +0xaffe
test "$x" = 45054
x=nope
type:cast[int]:int x +0xAFFE
test "$x" = 45054
x=nope
type:cast[int]:int x +0Xaffe
test "$x" = 45054
type:cast[int]:int x +1337
test "$x" = 1337
type:cast[int]:int x +0755
test "$x" = 493
type:cast[int]:int x +0
test "$x" = 0
x=nope
! type:cast[int]:int x +0x
test "$x" = nope
! type:cast[int]:int x
test "$x" = nope
! type:cast[int]:int x +
test "$x" = nope
! type:cast[int]:int x +yes
test "$x" = nope
! type:cast[int]:int x +FALSE
test "$x" = nope

type:cast[int]:int x -0xaffe
test "$x" = -45054
x=nope
type:cast[int]:int x -0xAFFE
test "$x" = -45054
x=nope
type:cast[int]:int x -0Xaffe
test "$x" = -45054
type:cast[int]:int x -1337
test "$x" = -1337
type:cast[int]:int x -0755
test "$x" = -493
type:cast[int]:int x -0
test "$x" = 0
x=nope
! type:cast[int]:int x -0x
test "$x" = nope
! type:cast[int]:int x
test "$x" = nope
! type:cast[int]:int x -
test "$x" = nope
! type:cast[int]:int x -yes
test "$x" = nope
! type:cast[int]:int x -FALSE
test "$x" = nope

# Single type matches
type:cast[int] x empty
test "$x" = 0
x=nope
! type:cast[int] x empty foo
test "$x" = nope
type:cast[int] x bool yes
test "$x" = 1
x=nope
! type:cast[int] x bool 2
test "$x" = nope
type:cast[int] x uint 0xAFFE
test "$x" = 45054
! type:cast[int] x uint -1
test "$x" = 45054
type:cast[int] x int +0755
test "$x" = 493
! type:cast[int] x int 0x
test "$x" = 493

# Multiple type matches
type:cast[int] x bool,empty
test "$x" = 0
x=nope
! type:cast[int] x bool,empty foo
test "$x" = nope
type:cast[int] x empty,bool
test "$x" = 0
x=nope
! type:cast[int] x empty,bool foo
test "$x" = nope
type:cast[int] x bool,empty,int -0755
test "$x" = -493
x=nope
! type:cast[int] x bool,empty,uint -0755
test "$x" = nope
