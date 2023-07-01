_bsda_err_=1
bsda:err:createECs() { :; }
bsda:err:raise() { local IFS; IFS=$'\n'; errno="${1}"; errmsg="${*}"; }
export LANG=C

. ../src/bsda_fmt.sh

  bsda:fmt:in a a=b b=c c=d d=e
  bsda:fmt:in b a=b b=c c=d d=e
  bsda:fmt:in c a=b b=c c=d d=e
  bsda:fmt:in d a=b b=c c=d d=e
! bsda:fmt:in e a=b b=c c=d d=e

  bsda:fmt:in axe axe=b bxe=c cxe=d dxe=e
  bsda:fmt:in bxe axe=b bxe=c cxe=d dxe=e
  bsda:fmt:in cxe axe=b bxe=c cxe=d dxe=e
  bsda:fmt:in dxe axe=b bxe=c cxe=d dxe=e
! bsda:fmt:in exe axe=b bxe=c cxe=d dxe=e

  bsda:fmt:in a a=$'foo\nbar' b=c c=d d=e
  bsda:fmt:in b a=$'foo\nbar' b=c c=d d=e
  bsda:fmt:in c a=$'foo\nbar' b=c c=d d=e
  bsda:fmt:in d a=$'foo\nbar' b=c c=d d=e
! bsda:fmt:in e a=$'foo\nbar' b=c c=d d=e

  bsda:fmt:in a a=b b=c c=d d=$'foo\nbar'
  bsda:fmt:in b a=b b=c c=d d=$'foo\nbar'
  bsda:fmt:in c a=b b=c c=d d=$'foo\nbar'
  bsda:fmt:in d a=b b=c c=d d=$'foo\nbar'
! bsda:fmt:in e a=b b=c c=d d=$'foo\nbar'

  bsda:fmt:in a a=b b=c c=$'foo\nbar' d=e
  bsda:fmt:in b a=b b=c c=$'foo\nbar' d=e
  bsda:fmt:in c a=b b=c c=$'foo\nbar' d=e
  bsda:fmt:in d a=b b=c c=$'foo\nbar' d=e
! bsda:fmt:in e a=b b=c c=$'foo\nbar' d=e

bsda:fmt:isarg a=
test "${errno}" = ""
bsda:fmt:isarg A=
test "${errno}" = ""
! bsda:fmt:isarg ö=
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt:isarg ẞ=
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt:isarg 1=
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt:isarg _=
test "${errno}" = E_BSDA_FMT_ARG && errno=

bsda:fmt:isarg a=x
test "${errno}" = ""
bsda:fmt:isarg A=x
test "${errno}" = ""
! bsda:fmt:isarg ö=x
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt:isarg ẞ=x
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt:isarg 1=x
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt:isarg _=x
test "${errno}" = E_BSDA_FMT_ARG && errno=

bsda:fmt:isarg aa=x
test "${errno}" = ""
bsda:fmt:isarg aA=x
test "${errno}" = ""
bsda:fmt:isarg a3=x
test "${errno}" = ""
bsda:fmt:isarg a_=x
test "${errno}" = ""
bsda:fmt:isarg Aa=x
test "${errno}" = ""
bsda:fmt:isarg AA=x
test "${errno}" = ""
bsda:fmt:isarg A3=x
test "${errno}" = ""
bsda:fmt:isarg A_=x
test "${errno}" = ""
! bsda:fmt:isarg öa=x
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt:isarg ẞa=x
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt:isarg 1a=x
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt:isarg _a=x
test "${errno}" = E_BSDA_FMT_ARG && errno=
bsda:fmt:isarg aaaa=x
test "${errno}" = ""
bsda:fmt:isarg a_1Z=x
test "${errno}" = ""
! bsda:fmt:isarg a_1?=x
test "${errno}" = E_BSDA_FMT_ARG && errno=

test 'foo{bar}baz'       = "$(bsda:fmt:sanitise 'foo{bar}baz')"
test 'foo\173bar\175baz' = "$(bsda:fmt:sanitise 'foo\{bar\}baz')"
test 'fo\\x'             = "$(bsda:fmt:sanitise 'fo\x')"
test 'fox\\'             = "$(bsda:fmt:sanitise 'fox\')"
test 'fo%%x'             = "$(bsda:fmt:sanitise 'fo%x')"
test 'fo%%%%%%x'         = "$(bsda:fmt:sanitise 'fo%%%x')"
test 'foo\${bar}baz'     = "$(bsda:fmt:sanitise 'foo${bar}baz')"

# some basic substitution tests
bsda:fmt str ''
test -z "${str}"
bsda:fmt str 'abc'
test "${str}" = 'abc'
bsda:fmt str 'abc\n\tfoo\'
test "${str}" = $'abc\n\tfoo\\'
bsda:fmt str 'abc{def}' def=
test "${str}" = 'abc'
bsda:fmt str '{abc}def' abc=
test "${str}" = 'def'
bsda:fmt str '{abc}{def:.(size)}' abc= def=....... size=3
test "${str}" = '...'
bsda:fmt str '{abc}{def:.(size)}' abc= def=....... size=3
test "${str}" = '...'
bsda:fmt str '{x}' x=foobar
test "${str}" = 'foobar'
bsda:fmt str '{str}.' str=barfoo
test "${str}" = 'barfoo.'
bsda:fmt str '{str}.{str}' str=barfoo
test "${str}" = 'barfoo.barfoo'

# printf type mismatch
bsda:fmt str 'a{str:x}a' a=3 b=4 str=
test "${str}" = 'a0a'
bsda:fmt str 'b{str:x}b' a=3 b=4 str=foobar
test "${str}" = 'b0b'

# variable in expression is not an integer
! bsda:fmt str '{a:(str)}' a=3 b=4 str=foobar
test "${errno}" = E_BSDA_FMT_TYPE && errno=
! bsda:fmt str '{a:(str)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_TYPE && errno=

# integer literals
bsda:fmt str '{str:(1234)}' a=3 b=4 str=
test "${#str}" = 1234
bsda:fmt str '{str:(0x12a)}' a=3 b=4 str=
test "${#str}" = 298
bsda:fmt str '{str:(0x12A)}' a=3 b=4 str=
test "${#str}" = 298
bsda:fmt str '{str:(0X12a)}' a=3 b=4 str=
test "${#str}" = 298
bsda:fmt str '{str:(0X12A)}' a=3 b=4 str=
test "${#str}" = 298
bsda:fmt str '{str:(0123)}' a=3 b=4 str=
test "${#str}" = 83
bsda:fmt str '{str:(+1234)}' a=3 b=4 str=
test "${#str}" = 1234
bsda:fmt str '{str:(+0x12a)}' a=3 b=4 str=
test "${#str}" = 298
bsda:fmt str '{str:(+0123)}' a=3 b=4 str=
test "${#str}" = 83
bsda:fmt str '{str:(-1234)}' a=3 b=4 str=
test "${#str}" = 1234
bsda:fmt str '{str:(-0x12a)}' a=3 b=4 str=
test "${#str}" = 298
bsda:fmt str '{str:(-0123)}' a=3 b=4 str=
test "${#str}" = 83

# shortest literals
bsda:fmt str '{str:(9)}' a=3 b=4 str=
test "${#str}" = 9
! bsda:fmt str '{str:(0x)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
bsda:fmt str '{str:(0x0)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(0xf)}' a=3 b=4 str=
test "${#str}" = 15
bsda:fmt str '{str:(0)}' a=3 b=4 str=
test "${#str}" = 0

# literal (dec) must be followed by operator
! bsda:fmt str '{str:(1234x)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(12340x)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(1234 x)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(-1234x)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(-12340x)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(-1234 x)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=

# literal (hex) must be followed by operator
! bsda:fmt str '{str:(0x12ax)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(0x12a0x)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(0x12a x)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(-0x12ax)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(-0x12a0x)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(-0x12a x)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=

# literal (oct) must be followed by operator
! bsda:fmt str '{str:(01238)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(012308)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(0123 8)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(-01238)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(-012308)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=
! bsda:fmt str '{str:(-0123 8)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR && errno=

# binary operators in expressions
bsda:fmt str '{str:(a % a)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(a % b)}' a=3 b=4 str=
test "${#str}" = 3
bsda:fmt str '{str:(b % a)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(a << a)}' a=3 b=4 str=
test "${#str}" = 24
bsda:fmt str '{str:(a << b)}' a=3 b=4 str=
test "${#str}" = 48
bsda:fmt str '{str:(b << a)}' a=3 b=4 str=
test "${#str}" = 32
bsda:fmt str '{str:(a >> a)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(a >> b)}' a=48 b=4 str=
test "${#str}" = 3
bsda:fmt str '{str:(b >> a)}' a=3 b=32 str=
test "${#str}" = 4
bsda:fmt str '{str:(a == a)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(a == b)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(b == a)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(a != a)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(a != b)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(b != a)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(a <= a)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(a <= b)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(b <= a)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(a >= a)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(a >= b)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(b >= a)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(a && a)}' a=3 b=0 str=
test "${#str}" = 1
bsda:fmt str '{str:(a && b)}' a=3 b=0 str=
test "${#str}" = 0
bsda:fmt str '{str:(b && a)}' a=3 b=0 str=
test "${#str}" = 0
bsda:fmt str '{str:(b && b)}' a=3 b=0 str=
test "${#str}" = 0
bsda:fmt str '{str:(a || a)}' a=3 b=0 str=
test "${#str}" = 1
bsda:fmt str '{str:(a || b)}' a=3 b=0 str=
test "${#str}" = 1
bsda:fmt str '{str:(b || a)}' a=3 b=0 str=
test "${#str}" = 1
bsda:fmt str '{str:(b || b)}' a=3 b=0 str=
test "${#str}" = 0
bsda:fmt str '{str:(a - a)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(a - b)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(b - a)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(a + a)}' a=3 b=4 str=
test "${#str}" = 6
bsda:fmt str '{str:(a + b)}' a=3 b=4 str=
test "${#str}" = 7
bsda:fmt str '{str:(b + a)}' a=3 b=4 str=
test "${#str}" = 7
bsda:fmt str '{str:(a * a)}' a=3 b=4 str=
test "${#str}" = 9
bsda:fmt str '{str:(a * b)}' a=3 b=4 str=
test "${#str}" = 12
bsda:fmt str '{str:(b * a)}' a=3 b=4 str=
test "${#str}" = 12
bsda:fmt str '{str:(a / a)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(a / b)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(b / a)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(a < a)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(a < b)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(b < a)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(a > a)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(a > b)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(b > a)}' a=3 b=4 str=
test "${#str}" = 1
bsda:fmt str '{str:(a & a)}' a=3 b=4 str=
test "${#str}" = 3
bsda:fmt str '{str:(a & b)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(b & a)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(a | a)}' a=3 b=4 str=
test "${#str}" = 3
bsda:fmt str '{str:(a | b)}' a=3 b=4 str=
test "${#str}" = 7
bsda:fmt str '{str:(b | a)}' a=3 b=4 str=
test "${#str}" = 7
bsda:fmt str '{str:(a ^ a)}' a=3 b=4 str=
test "${#str}" = 0
bsda:fmt str '{str:(a ^ b)}' a=3 b=4 str=
test "${#str}" = 7
bsda:fmt str '{str:(b ^ a)}' a=3 b=4 str=
test "${#str}" = 7

# ternary operator
bsda:fmt str '{str:(1 ? a : b)}' a=3 b=4 str=
test "${#str}" = 3
bsda:fmt str '{str:(0 ? a : b)}' a=3 b=4 str=
test "${#str}" = 4
bsda:fmt str '{str:(a < b ? a : b)}' a=3 b=4 str=
test "${#str}" = 3
bsda:fmt str '{str:(a > b ? a : b)}' a=3 b=4 str=
test "${#str}" = 4

# assignment
! bsda:fmt str '{str:(a %= b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a -- b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a-- b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a --b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a--b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a ++ b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a++ b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a ++b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a++b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a = b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a -= b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a += b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a &= b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a |= b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a ^= b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a ?= b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=
! bsda:fmt str '{str:(a := b)}' a=3 b=4 str=
test "${errno}" = E_BSDA_FMT_EXPR_ASSIGN && errno=

# parentheses
bsda:fmt str '{str:(((a)))}' a=3 b=4 str=
test "${#str}" = 3
bsda:fmt str '{str:( ( ( a)))}' a=3 b=4 str=
test "${#str}" = 3
bsda:fmt str '{str:(((a ) ) )}' a=3 b=4 str=
test "${#str}" = 3
bsda:fmt str '{str:( ( ( a ) ) )}' a=3 b=4 str=
test "${#str}" = 3
bsda:fmt str '{str:(a+a*b)}' a=3 b=4 str=
test "${#str}" = 15
bsda:fmt str '{str:((a)+(a)*(b))}' a=3 b=4 str=
test "${#str}" = 15
bsda:fmt str '{str:((a+a)*b)}' a=3 b=4 str=
test "${#str}" = 24
bsda:fmt str '{str:(((a)+a)*b)}' a=3 b=4 str=
test "${#str}" = 24
bsda:fmt str '{str:(a+(a*b))}' a=3 b=4 str=
test "${#str}" = 15
bsda:fmt str '{str:(a+(a*(b)))}' a=3 b=4 str=
test "${#str}" = 15

# argument checking
bsda:fmt str '' a=
test "${errno}" = ""
bsda:fmt str '' A=
test "${errno}" = ""
! bsda:fmt str '' ö=
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt str '' ẞ=
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt str '' 1=
test "${errno}" = E_BSDA_FMT_ARG && errno=
! bsda:fmt str '' _=
test "${errno}" = E_BSDA_FMT_ARG && errno=
bsda:fmt str '' A_=x
test "${errno}" = ""
! bsda:fmt str '' öa=x
test "${errno}" = E_BSDA_FMT_ARG && errno=
bsda:fmt str '{str:(a)}' a=3 str=
test "${#str}" = 3
bsda:fmt str '{str:(a)}' a=0xa str=
test "${#str}" = 10
bsda:fmt str '{str:(a)}' a=010 str=
test "${#str}" = 8
! bsda:fmt str '{str:(a)}' a= str=
test "${errno}" = E_BSDA_FMT_TYPE && errno=0
! bsda:fmt str '{str:(a)}' a=fox str=
test "${errno}" = E_BSDA_FMT_TYPE && errno=0
! bsda:fmt str '{str:(a)}' a=\  str=
test "${errno}" = E_BSDA_FMT_TYPE && errno=0
! bsda:fmt str '{str:(a)}' a=0x1fz str=
test "${errno}" = E_BSDA_FMT_TYPE && errno=0

# multiple substitutions
bsda:fmt str '{a}/{a}/{a}' a=X b=Y c=Z
test "${str}" = 'X/X/X'
bsda:fmt str '{a}/{b}/{a}' a=X b=Y c=Z
test "${str}" = 'X/Y/X'
bsda:fmt str '{a}/{b}/{c}' a=X b=Y c=Z
test "${str}" = 'X/Y/Z'
bsda:fmt str '{c}/{b}/{a}' a=X b=Y c=Z
test "${str}" = 'Z/Y/X'
! bsda:fmt str '{c}/{d}/{a}' a=X b=Y c=Z
test "${errno}" = E_BSDA_FMT_SUB
! bsda:fmt str 'a{a{a}}' a=X b=Y c=Z
test "${errno}" = E_BSDA_FMT_SUB_ID

# test printing variants
bsda:fmt str '{a}.{b}/{c}' a=X b=Y c=Z
test "${str}" = "$(bsda:fmt:printf '{a}.{b}/{c}' a=X b=Y c=Z)"
test "${str}" = "$(bsda:fmt     '' '{a}.{b}/{c}' a=X b=Y c=Z)"
bsda:fmt str '{a}\n\n' a=X b=Y c=Z
test "${str}" = "$(bsda:fmt:printf '{a}\n\n' a=X b=Y c=Z)"
test "${str}" = "$(bsda:fmt     '' '{a}\n\n' a=X b=Y c=Z)"

# test scaling functions

bsda:fmt:iec v p 1            && test "$p" = ""   -a "$v" = "1"
bsda:fmt:iec v p 12           && test "$p" = ""   -a "$v" = "12"
bsda:fmt:iec v p 123          && test "$p" = ""   -a "$v" = "123"
bsda:fmt:iec v p 1023         && test "$p" = "Ki" -a "$v" = "1.0"
bsda:fmt:iec v p 10234        && test "$p" = "Ki" -a "$v" = "10"
bsda:fmt:iec v p 102345       && test "$p" = "Ki" -a "$v" = "100"
bsda:fmt:iec v p 1023487      && test "$p" = "Ki" -a "$v" = "999"
bsda:fmt:iec v p 1023488      && test "$p" = "Mi" -a "$v" = "1.0"
bsda:fmt:iec v p 1048051711   && test "$p" = "Mi" -a "$v" = "999"
bsda:fmt:iec v p 1048051712   && test "$p" = "Gi" -a "$v" = "1.0"

bsda:fmt:iec v p 1          3 && test "$p" = ""   -a "$v" = "1"
bsda:fmt:iec v p 12         3 && test "$p" = ""   -a "$v" = "12"
bsda:fmt:iec v p 123        3 && test "$p" = ""   -a "$v" = "123"
bsda:fmt:iec v p 1023       3 && test "$p" = "Ki" -a "$v" = "1.0"
bsda:fmt:iec v p 10234      3 && test "$p" = "Ki" -a "$v" = "10"
bsda:fmt:iec v p 102345     3 && test "$p" = "Ki" -a "$v" = "100"
bsda:fmt:iec v p 1023487    3 && test "$p" = "Ki" -a "$v" = "999"
bsda:fmt:iec v p 1023488    3 && test "$p" = "Mi" -a "$v" = "1.0"
bsda:fmt:iec v p 1048051711 3 && test "$p" = "Mi" -a "$v" = "999"
bsda:fmt:iec v p 1048051712 3 && test "$p" = "Gi" -a "$v" = "1.0"

bsda:fmt:iec v p 1          4 && test "$p" = ""   -a "$v" = "1"
bsda:fmt:iec v p 12         4 && test "$p" = ""   -a "$v" = "12"
bsda:fmt:iec v p 123        4 && test "$p" = ""   -a "$v" = "123"
bsda:fmt:iec v p 1023       4 && test "$p" = "Ki" -a "$v" = "1.00"
bsda:fmt:iec v p 10234      4 && test "$p" = "Ki" -a "$v" = "9.99"
bsda:fmt:iec v p 102345     4 && test "$p" = "Ki" -a "$v" = "99.9"
bsda:fmt:iec v p 1023487    4 && test "$p" = "Ki" -a "$v" = "999"
bsda:fmt:iec v p 1023488    4 && test "$p" = "Mi" -a "$v" = "0.98"
bsda:fmt:iec v p 1048051711 4 && test "$p" = "Mi" -a "$v" = "999"
bsda:fmt:iec v p 1048051712 4 && test "$p" = "Gi" -a "$v" = "0.98"

bsda:fmt:iec v p 1          5 && test "$p" = ""   -a "$v" = "1"
bsda:fmt:iec v p 12         5 && test "$p" = ""   -a "$v" = "12"
bsda:fmt:iec v p 123        5 && test "$p" = ""   -a "$v" = "123"
bsda:fmt:iec v p 1023       5 && test "$p" = "Ki" -a "$v" = "0.999"
bsda:fmt:iec v p 10234      5 && test "$p" = "Ki" -a "$v" = "9.994"
bsda:fmt:iec v p 102345     5 && test "$p" = "Ki" -a "$v" = "99.95"
bsda:fmt:iec v p 1023948    5 && test "$p" = "Ki" -a "$v" = "999.9"
bsda:fmt:iec v p 1023949    5 && test "$p" = "Mi" -a "$v" = "0.977"
bsda:fmt:iec v p 1048523571 5 && test "$p" = "Mi" -a "$v" = "999.9"
bsda:fmt:iec v p 1048523572 5 && test "$p" = "Gi" -a "$v" = "0.977"

bsda:fmt:si v p 1           && test "$p" = ""  -a "$v" = "1"
bsda:fmt:si v p 12          && test "$p" = ""  -a "$v" = "12"
bsda:fmt:si v p 123         && test "$p" = ""  -a "$v" = "123"
bsda:fmt:si v p 1234        && test "$p" = "k" -a "$v" = "1.2"
bsda:fmt:si v p 12345       && test "$p" = "k" -a "$v" = "12"
bsda:fmt:si v p 123456      && test "$p" = "k" -a "$v" = "123"
bsda:fmt:si v p 1249999     && test "$p" = "M" -a "$v" = "1.2"
bsda:fmt:si v p 1250000     && test "$p" = "M" -a "$v" = "1.3"
bsda:fmt:si v p 12499999    && test "$p" = "M" -a "$v" = "12"
bsda:fmt:si v p 12500000    && test "$p" = "M" -a "$v" = "13"
bsda:fmt:si v p 99499999    && test "$p" = "M" -a "$v" = "99"
bsda:fmt:si v p 99500000    && test "$p" = "M" -a "$v" = "100"
bsda:fmt:si v p 123499999   && test "$p" = "M" -a "$v" = "123"
bsda:fmt:si v p 123500000   && test "$p" = "M" -a "$v" = "124"
bsda:fmt:si v p 999499999   && test "$p" = "M" -a "$v" = "999"
bsda:fmt:si v p 999500000   && test "$p" = "G" -a "$v" = "1.0"

bsda:fmt:si v p 1         3 && test "$p" = ""  -a "$v" = "1"
bsda:fmt:si v p 12        3 && test "$p" = ""  -a "$v" = "12"
bsda:fmt:si v p 123       3 && test "$p" = ""  -a "$v" = "123"
bsda:fmt:si v p 1234      3 && test "$p" = "k" -a "$v" = "1.2"
bsda:fmt:si v p 12345     3 && test "$p" = "k" -a "$v" = "12"
bsda:fmt:si v p 123456    3 && test "$p" = "k" -a "$v" = "123"
bsda:fmt:si v p 1249999   3 && test "$p" = "M" -a "$v" = "1.2"
bsda:fmt:si v p 1250000   3 && test "$p" = "M" -a "$v" = "1.3"
bsda:fmt:si v p 12499999  3 && test "$p" = "M" -a "$v" = "12"
bsda:fmt:si v p 12500000  3 && test "$p" = "M" -a "$v" = "13"
bsda:fmt:si v p 99499999  3 && test "$p" = "M" -a "$v" = "99"
bsda:fmt:si v p 99500000  3 && test "$p" = "M" -a "$v" = "100"
bsda:fmt:si v p 123499999 3 && test "$p" = "M" -a "$v" = "123"
bsda:fmt:si v p 123500000 3 && test "$p" = "M" -a "$v" = "124"
bsda:fmt:si v p 999499999 3 && test "$p" = "M" -a "$v" = "999"
bsda:fmt:si v p 999500000 3 && test "$p" = "G" -a "$v" = "1.0"

bsda:fmt:si v p 1         4 && test "$p" = ""  -a "$v" = "1"
bsda:fmt:si v p 12        4 && test "$p" = ""  -a "$v" = "12"
bsda:fmt:si v p 123       4 && test "$p" = ""  -a "$v" = "123"
bsda:fmt:si v p 1234      4 && test "$p" = "k" -a "$v" = "1.23"
bsda:fmt:si v p 12345     4 && test "$p" = "k" -a "$v" = "12.3"
bsda:fmt:si v p 123456    4 && test "$p" = "k" -a "$v" = "123"
bsda:fmt:si v p 1234999   4 && test "$p" = "M" -a "$v" = "1.23"
bsda:fmt:si v p 1235000   4 && test "$p" = "M" -a "$v" = "1.24"
bsda:fmt:si v p 12349999  4 && test "$p" = "M" -a "$v" = "12.3"
bsda:fmt:si v p 12350000  4 && test "$p" = "M" -a "$v" = "12.4"
bsda:fmt:si v p 99949999  4 && test "$p" = "M" -a "$v" = "99.9"
bsda:fmt:si v p 99950000  4 && test "$p" = "M" -a "$v" = "100"
bsda:fmt:si v p 123499999 4 && test "$p" = "M" -a "$v" = "123"
bsda:fmt:si v p 123500000 4 && test "$p" = "M" -a "$v" = "124"
bsda:fmt:si v p 999499999 4 && test "$p" = "M" -a "$v" = "999"
bsda:fmt:si v p 999500000 4 && test "$p" = "G" -a "$v" = "1.00"

bsda:fmt:si v p 1         5 && test "$p" = ""  -a "$v" = "1"
bsda:fmt:si v p 12        5 && test "$p" = ""  -a "$v" = "12"
bsda:fmt:si v p 123       5 && test "$p" = ""  -a "$v" = "123"
bsda:fmt:si v p 1234      5 && test "$p" = "k" -a "$v" = "1.234"
bsda:fmt:si v p 12345     5 && test "$p" = "k" -a "$v" = "12.35"
bsda:fmt:si v p 123456    5 && test "$p" = "k" -a "$v" = "123.5"
bsda:fmt:si v p 1234499   5 && test "$p" = "M" -a "$v" = "1.234"
bsda:fmt:si v p 1234500   5 && test "$p" = "M" -a "$v" = "1.235"
bsda:fmt:si v p 12344999  5 && test "$p" = "M" -a "$v" = "12.34"
bsda:fmt:si v p 12345000  5 && test "$p" = "M" -a "$v" = "12.35"
bsda:fmt:si v p 99994999  5 && test "$p" = "M" -a "$v" = "99.99"
bsda:fmt:si v p 99995000  5 && test "$p" = "M" -a "$v" = "100.0"
bsda:fmt:si v p 123449999 5 && test "$p" = "M" -a "$v" = "123.4"
bsda:fmt:si v p 123450000 5 && test "$p" = "M" -a "$v" = "123.5"
bsda:fmt:si v p 999949999 5 && test "$p" = "M" -a "$v" = "999.9"
bsda:fmt:si v p 999950000 5 && test "$p" = "G" -a "$v" = "1.000"

bsda:fmt:unit v   B 12345678   && test "$v" = 12345678
bsda:fmt:unit v   b 12345678   && test "$v" = 12345678
bsda:fmt:unit v  '' 12345678   && test "$v" = 12345678
bsda:fmt:unit v  '' 12345678 0 && test "$v" = 12345678
bsda:fmt:unit v  '' 12345678 1 && test "$v" = 12345678.0
bsda:fmt:unit v  '' 12345678 2 && test "$v" = 12345678.00
bsda:fmt:unit v  '' 12345678 4 && test "$v" = 12345678.0000
bsda:fmt:unit v  kB 12345678   && test "$v" = 12346
bsda:fmt:unit v  kb 12345678   && test "$v" = 12346
bsda:fmt:unit v  k  12345678   && test "$v" = 12346
bsda:fmt:unit v  k  12345678 0 && test "$v" = 12346
bsda:fmt:unit v  k  12345678 1 && test "$v" = 12345.7
bsda:fmt:unit v  k  12345678 2 && test "$v" = 12345.68
bsda:fmt:unit v  k  12345678 4 && test "$v" = 12345.6780
bsda:fmt:unit v KiB 12345678   && test "$v" = 12056
bsda:fmt:unit v Kib 12345678   && test "$v" = 12056
bsda:fmt:unit v Ki  12345678   && test "$v" = 12056
bsda:fmt:unit v Ki  12345678 0 && test "$v" = 12056
bsda:fmt:unit v Ki  12345678 1 && test "$v" = 12056.3
bsda:fmt:unit v Ki  12345678 2 && test "$v" = 12056.33
bsda:fmt:unit v Ki  12345678 4 && test "$v" = 12056.3262
bsda:fmt:unit v  M  12345678 4 && test "$v" = 12.3457
bsda:fmt:unit v Mi  12345678 4 && test "$v" = 11.7738
bsda:fmt:unit v  G  12345678 4 && test "$v" = 0.0123
bsda:fmt:unit v Gi  12345678 4 && test "$v" = 0.0115
