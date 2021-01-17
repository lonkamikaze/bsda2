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
