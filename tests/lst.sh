. ../src/lst.sh

#
# Verify record separator ${RS} is set by log/rec/csv but not lst.
#

lst.check_log() { test "${RS}" = $'\n'; }
lst.check_rec() { test "${RS}" = $'\036'; }
lst.check_csv() { test "${RS}" = ,; }
lst.check_col() { test "${RS}" = :; }

! RS=        lst x.check_log
  RS=$'\n'   lst x.check_log
! RS=$'\036' lst x.check_log
! RS=,       lst x.check_log
! RS=:       lst x.check_log

! RS=        lst x.check_rec
! RS=$'\n'   lst x.check_rec
  RS=$'\036' lst x.check_rec
! RS=,       lst x.check_rec
! RS=:       lst x.check_rec

! RS=        lst x.check_csv
! RS=$'\n'   lst x.check_csv
! RS=$'\036' lst x.check_csv
  RS=,       lst x.check_csv
! RS=:       lst x.check_csv

! RS=        lst x.check_col
! RS=$'\n'   lst x.check_col
! RS=$'\036' lst x.check_col
! RS=,       lst x.check_col
  RS=:       lst x.check_col

  log x.check_log
! rec x.check_log
! csv x.check_log

! log x.check_rec
  rec x.check_rec
! csv x.check_rec

! log x.check_csv
! rec x.check_csv
  csv x.check_csv

! log x.check_col
! rec x.check_col
! csv x.check_col

#
# lst:unpack
#

lst.check_name_i() { test "$1" = "$3"; }
lst.check_index_i() { test "$2" = "$3"; }

! lst foobar[2+3].check_name fox
  lst foobar[2+3].check_name foobar

! lst foobar[2+3].check_index 5
  lst foobar[2+3].check_index 2+3
  lst foobar['2 + 3'].check_index '2 + 3'

(
	#
	# a[i] calls lst.get_i
	#
	array=
	index=
	lst.get_i() { array="$1"; index="$2"; }
	rec a[12]
	test "${array}" = a
	test "${index}" = 12
	rec foo_bar['index += 1']
	test "${array}" = foo_bar
	test "${index}" = 'index += 1'

	#
	# a[i]= calls lst.set_i
	#
	array=
	index=
	value=
	lst.set_i() { array="$1"; index="$2"; value="$3"; }
	rec a[12]= 1337
	test "${array}" = a
	test "${index}" = 12
	test "${value}" = 1337
	rec foo_bar['index += 1']= faßtföod
	test "${array}" = foo_bar
	test "${index}" = 'index += 1'
	test "${value}" = faßtföod
)

#
# a=
#

log l= foo bar baz '' bam ''
test "$l" = $'foo\nbar\nbaz\n\nbam\n\n'
rec r= foo bar baz '' bam ''
test "$r" = $'foo\036bar\036baz\036\036bam\036\036'
csv c=
test -z "$c"

#
# a[i] aka a[i].get aka a.get_i
#

log a= foo bar 'bird in the sky' 'gold mine'
x=x
! log a[0] x
test "${x}" = x
log a[1] x
test "${x}" = 'foo'
log a[3] x
test "${x}" = 'bird in the sky'
x=x
! log a[5] x
test "${x}" = x
! log a[6] x
test "${x}" = x
log a[-1] x
test "${x}" = 'gold mine'
log a[-4] x
test "${x}" = 'foo'
x=x
! log a[-5] x
test "${x}" = x
! log a[-6] x
test "${x}" = x

v=x
! log a[i=0] v
test "${v}" = 'x'
log a[i+=1] v
test "${v}" = foo
test "${i}" -eq 1
log a[i+=1] v
test "${v}" = bar
test "${i}" -eq 2
log a[i+=1] v
test "${v}" = 'bird in the sky'
test "${i}" -eq 3
log a[i+=1] v
test "${v}" = 'gold mine'
test "${i}" -eq 4
v=x
! log a[i+=1] v
test "${v}" = 'x'
test "${i}" -eq 5
! log a[i+=1] v
test "${v}" = 'x'
test "${i}" -eq 6

log a[i=-1] v
test "${v}" = 'gold mine'
test "${i}" -eq -1
log a[i-=1] v
test "${v}" = 'bird in the sky'
test "${i}" -eq -2
log a[i-=1] v
test "${v}" = 'bar'
test "${i}" -eq -3
log a[i-=1] v
test "${v}" = 'foo'
test "${i}" -eq -4
v=x
! log a[i-=1] v
test "${v}" = 'x'
test "${i}" -eq -5
! log a[i-=1] v
test "${v}" = 'x'
test "${i}" -eq -6

log l= foo bar baz '' bam ''
test "$l" = $'foo\nbar\nbaz\n\nbam\n\n'
log l[-1] x
test "$x" = bam
log l[-2] x
test "$x" = baz
log l[-4] x
test "$x" = foo
! log l[-5] x
test "$x" = foo
test "$l" = $'foo\nbar\nbaz\n\nbam\n\n'

rec r= foo bar baz '' bam ''
test "$r" = $'foo\036bar\036baz\036\036bam\036\036'
x=1
rec r[-1] x
test "$x" = ''
rec r[-2] x
test "$x" = bam
rec r[-4] x
test "$x" = baz
! rec r[-7] x
test "$x" = baz
test "$r" = $'foo\036bar\036baz\036\036bam\036\036'

#
# a[i]= aka a[i].set aka a.set_i
#

log l= foo bar baz '' bam ''
! log l[6]= x
test "$l" = $'foo\nbar\nbaz\n\nbam\n\n'
log l[-1]= x
test "$l" = $'foo\nbar\nbaz\nx\n'

rec r= foo bar baz '' bam ''
test "$r" = $'foo\036bar\036baz\036\036bam\036\036'
rec r[6]= x
test "$r" = $'foo\036bar\036baz\036\036bam\036x\036'
! rec r[0]= x
! rec r[7]= x
test "$r" = $'foo\036bar\036baz\036\036bam\036x\036'
rec r[-2]= y
test "$r" = $'foo\036bar\036baz\036\036y\036x\036'
! rec r[-7]= y
test "$r" = $'foo\036bar\036baz\036\036y\036x\036'

i=0
while rec r[i+=1]= $i; do :; done
test "$r" = $'0\0361\0362\0363\0364\0365\036'

#
# a[i].rm aka a.rm_i
#

log l= foo bar baz '' bam ''
test "$l" = $'foo\nbar\nbaz\n\nbam\n\n'
log l[-2].rm
test "$l" = $'foo\nbar\nbam\n'

rec r= foo bar baz '' bam ''
test "$r" = $'foo\036bar\036baz\036\036bam\036\036'
rec r[2].rm
test "$r" = $'foo\036baz\036\036bam\036\036'
rec r[-1].rm
test "$r" = $'foo\036baz\036\036bam\036'
! rec r[0].rm
test "$r" = $'foo\036baz\036\036bam\036'
! rec r[-5].rm
test "$r" = $'foo\036baz\036\036bam\036'

#
# a.resize
#

rec a= 1 2 3 4
test "$a" = $'1\0362\0363\0364\036'
rec a.resize 6
test "$a" = $'1\0362\0363\0364\036\036\036'
rec a.resize 3
test "$a" = $'1\0362\0363\036'
rec a.resize 5 X
test "$a" = $'1\0362\0363\036X\036X\036'

rec a= '' '' 3 '' 5 ''
test "$a" = $'\036\0363\036\0365\036\036'
rec a.resize 8
test "$a" = $'\036\0363\036\0365\036\036\036\036'
rec a.resize 10 ...
test "$a" = $'\036\0363\036\0365\036\036\036\036...\036...\036'

log a= '' '' 3 '' 5 ''
test "$a" = $'\n\n3\n\n5\n\n'
log a.resize 8
test "$a" = $'3\n5\n\n\n\n\n\n\n'

#
# a.push_front
# a.peek_front
#

log a=
test -z "$a"
log a.push_front
test -z "$a"
! log a.peek_front
log a.push_front 'fire in the hole'
test "$a" = $'fire in the hole\n'
log a.peek_front x
test "$x" = 'fire in the hole'
log a.push_front xXx '...oooOOO(foo)' '(bar)OOOooo...'
test "$a" = $'(bar)OOOooo...\n...oooOOO(foo)\nxXx\nfire in the hole\n'
log a.peek_front x
test "$x" = '(bar)OOOooo...'
log a.push_front '' '' ''
test "$a" = $'\n\n\n(bar)OOOooo...\n...oooOOO(foo)\nxXx\nfire in the hole\n'
log a.peek_front x
test "$x" = ''
log a.push_front x ''
test "$a" = $'\nx\n\n\n\n(bar)OOOooo...\n...oooOOO(foo)\nxXx\nfire in the hole\n'
x=1
log a.peek_front x
test "$x" = ''

#
# a.push_back
# a.peek_back
#

log a=
test -z "$a"
log a.push_back
test -z "$a"
! log a.peek_back
log a.push_back 'fire in the hole'
test "$a" = $'fire in the hole\n'
log a.peek_back x
test "$x" = 'fire in the hole'
log a.push_back xXx '...oooOOO(foo)' '(bar)OOOooo...'
test "$a" = $'fire in the hole\nxXx\n...oooOOO(foo)\n(bar)OOOooo...\n'
log a.peek_back x
test "$x" = '(bar)OOOooo...'
log a.push_back '' '' ''
test "$a" = $'fire in the hole\nxXx\n...oooOOO(foo)\n(bar)OOOooo...\n\n\n\n'
log a.peek_back x
test "$x" = ''
log a.push_back x ''
test "$a" = $'fire in the hole\nxXx\n...oooOOO(foo)\n(bar)OOOooo...\n\n\n\nx\n\n'
log a.peek_back x
test "$x" = ''

#
# a.pop_front
#

log a=
test -z "$a"
log a.pop_front; test $? -eq 1
log a= 'this is' sparta
test "$a" = $'this is\nsparta\n'
log a.pop_front x
test "$x" = 'this is'
test "$a" = $'sparta\n'
log a= 'this is' sparta recursively pop values from array
log a.pop_front x0 x1 x2 x3
test "$x0" = 'this is'
test "$x1" = sparta
test "$x2" = recursively
test "$x3" = pop
test "$a" = $'values\nfrom\narray\n'
log a.pop_front x0 x1 x2 x3; test $? -eq 4
test "$x0" = values
test "$x1" = from
test "$x2" = array
test "$x3" = pop
test -z "$a"
log a= a b '' d e '' g h ''
test "$a" = $'a\nb\n\nd\ne\n\ng\nh\n\n'
log a.pop_front x0 x1 x2 x3
test "$x0" = a
test "$x1" = b
test "$x2" = ''
test "$x3" = d
test "$a" = $'e\n\ng\nh\n\n'
log a.pop_front x0 x1 x2 x3
test "$x0" = e
test "$x1" = ''
test "$x2" = g
test "$x3" = h
test "$a" = $'\n'
log a.pop_front x0 x1 x2 x3; test $? -eq 2
test "$x0" = ''
test "$x1" = ''
test "$x2" = g
test "$x3" = h
test -z "$a"

#
# a.pop_back
#

log a=
test -z "$a"
log a.pop_back; test $? -eq 1
log a= 'this is' sparta
test "$a" = $'this is\nsparta\n'
log a.pop_back x
test "$x" = sparta
test "$a" = $'this is\n'
log a= 'this is' sparta recursively pop values from array
log a.pop_back x0 x1 x2 x3
test "$x0" = array
test "$x1" = from
test "$x2" = values
test "$x3" = pop
test "$a" = $'this is\nsparta\nrecursively\n'
log a.pop_back x0 x1 x2 x3; test $? -eq 4
test "$x0" = recursively
test "$x1" = sparta
test "$x2" = 'this is'
test "$x3" = pop
test -z "$a"
log a= a b '' d e '' g h ''
test "$a" = $'a\nb\n\nd\ne\n\ng\nh\n\n'
log a.pop_back x0 x1 x2 x3
test "$x0" = ''
test "$x1" = h
test "$x2" = g
test "$x3" = ''
test "$a" = $'a\nb\n\nd\ne\n'
log a.pop_back x0 x1 x2 x3
test "$x0" = e
test "$x1" = d
test "$x2" = ''
test "$x3" = b
test "$a" = $'a\n'
log a.pop_back x0 x1 x2 x3; test $? -eq 2
test "$x0" = a
test "$x1" = d
test "$x2" = ''
test "$x3" = b
test -z "$a"

#
# a.rm_first
#

log a=
test -z "$a"
log a.rm_first; test $? -eq 1
log a= a b c '' a b c '' a b c ''
test "$a" = $'a\nb\nc\n\na\nb\nc\n\na\nb\nc\n\n'
log a.rm_first
test "$a" = $'a\nb\nc\na\nb\nc\n\na\nb\nc\n\n'
log a.rm_first '' '' ''; test $? -eq 3
test "$a" = $'a\nb\nc\na\nb\nc\na\nb\nc\n'
log a.rm_first d; test $? -eq 1
test "$a" = $'a\nb\nc\na\nb\nc\na\nb\nc\n'
log a.rm_first a c
test "$a" = $'b\na\nb\nc\na\nb\nc\n'

#
# a.rm_last
#

log a=
test -z "$a"
log a.rm_last; test $? -eq 1
log a= a b c '' a b c '' a b c ''
test "$a" = $'a\nb\nc\n\na\nb\nc\n\na\nb\nc\n\n'
log a.rm_last
test "$a" = $'a\nb\nc\n\na\nb\nc\n\na\nb\nc\n'
log a.rm_last '' '' ''; test $? -eq 3
test "$a" = $'a\nb\nc\na\nb\nc\na\nb\nc\n'
log a.rm_last d; test $? -eq 1
test "$a" = $'a\nb\nc\na\nb\nc\na\nb\nc\n'
log a.rm_last a c
test "$a" = $'a\nb\nc\na\nb\nc\nb\n'

#
# a.count
#

rec a=
test -z "$a"
rec a.count n
test "$n" -eq 0
rec a= 'foo bar' '' baz bam keks dose
test "$a" = $'foo bar\036\036baz\036bam\036keks\036dose\036'
rec a.count n
test "$n" -eq 6

log a=
test -z "$a"
log a.count n
test "$n" -eq 0
log a= 'foo bar' '' baz bam keks dose
test "$a" = $'foo bar\n\nbaz\nbam\nkeks\ndose\n'
log a.count n
test "$n" -eq 5

#
# a.contains
# a.contains_any
# a.contains_all
#

log a=
test -z "$a"
! log a.contains
! log a.contains ''
  log a.contains_all
! log a.contains_all ''
! log a.contains_any
! log a.contains_any ''

log a= 'foo bar' '' baz bam keks dose
! log a.contains
  log a.contains ''
  log a.contains_all
  log a.contains_all ''
! log a.contains_any
  log a.contains_any ''
! log a.contains foo
! log a.contains_all foo
! log a.contains_any foo
  log a.contains keks
! log a.contains_all foo keks
  log a.contains_any foo keks
  log a.contains 'foo bar'
  log a.contains_all 'foo bar' keks
  log a.contains_any 'foo bar' keks
! log a.contains_all 'foo bar' koks
  log a.contains_any 'foo bar' koks

#
# a.is_defined
# a.is_undefined
# a.is_empty
# a.is_not_empty
#

unset a
! rec a.is_defined
  rec a.is_undefined
  rec a.is_empty
! rec a.is_not_empty

rec a=
  rec a.is_defined
! rec a.is_undefined
  rec a.is_empty
! rec a.is_not_empty

rec a.push_back ''
  rec a.is_defined
! rec a.is_undefined
! rec a.is_empty
  rec a.is_not_empty

rec a.push_back keks dose
  rec a.is_defined
! rec a.is_undefined
! rec a.is_empty
  rec a.is_not_empty

unset a
! log a.is_defined
  log a.is_undefined
  log a.is_empty
! log a.is_not_empty

log a=
  log a.is_defined
! log a.is_undefined
  log a.is_empty
! log a.is_not_empty

log a.push_back ''
  log a.is_defined
! log a.is_undefined
! log a.is_empty
  log a.is_not_empty

log a.push_back keks dose
  log a.is_defined
! log a.is_undefined
! log a.is_empty
  log a.is_not_empty

#
# a aka a.print
#

(
	rs=
	lst_print=
	lst.print() { local IFS; IFS=,; rs="${RS}"; lst_print="$*"; }
	log a
	test "${lst_print}" = a
	test "${rs}" = $'\n'
	csv b c d
	test "${lst_print}" = b,c,d
	test "${rs}" = ,
)

log a= foo bar '' baz
test "$a" = $'foo\nbar\n\nbaz\n'
test "$(ORS=, log a)" = foo,bar,baz
log b= bang '' boom bang
test "$(ORS=' ' log a b)" = 'foo bar baz bang boom bang'

rec a= foo bar '' baz
test "$a" = $'foo\036bar\036\036baz\036'
test "$(ORS=- rec a)" = foo-bar--baz
rec b= bang '' boom bang
test "$b" = $'bang\036\036boom\036bang\036'
test "$(ORS=* rec a b)" = foo*bar**baz*bang**boom*bang
test "$(ORS=$'\n' rec a a)" = $'foo\nbar\n\nbaz\nfoo\nbar\n\nbaz'

#
# a.printf
#

rec a= foo bar '' baz
test "$a" = $'foo\036bar\036\036baz\036'
test "$(rec a.printf '[%s]\n')" = $'[foo]\n[bar]\n[]\n[baz]'

log a= foo bar '' baz
test "$a" = $'foo\nbar\n\nbaz\n'
test "$(log a.printf '[%s]\n')" = $'[foo]\n[bar]\n[baz]'

#
# a.append
#

log a= 'foo bar' '' baz bam keks dose
log b= '' '' ''
log c=
log d= 'this is the' end
log a.append b c d
test "$a" = $'foo bar\n\nbaz\nbam\nkeks\ndose\n\n\n\nthis is the\nend\n'

#
# a.set_irs
# a.set_ors
# a.set_ifs
#

unset IRS ORS IFS
log a.set_irs
test "${IRS}" = $'\n'
test -z "${ORS+1}"
test -z "${IFS+1}"

unset IRS ORS IFS
log a.set_ors
test -z "${IRS+1}"
test "${ORS}" = $'\n'
test -z "${IFS+1}"

unset IRS ORS IFS
log a.set_ifs
test -z "${IRS+1}"
test -z "${ORS+1}"
test "${IFS}" = $'\n'

unset IRS ORS IFS
rec a.set_irs
test "${IRS}" = $'\036'
test -z "${ORS+1}"
test -z "${IFS+1}"

unset IRS ORS IFS
rec a.set_ors
test -z "${IRS+1}"
test "${ORS}" = $'\036'
test -z "${IFS+1}"

unset IRS ORS IFS
rec a.set_ifs
test -z "${IRS+1}"
test -z "${ORS+1}"
test "${IFS}" = $'\036'

#
# a=cat aka lst:cat
#

(
	lst_cat=
	rs=
	lst:cat() { local IFS; IFS=,; rs="${RS}" lst_cat="$*"; }
	log a=cat foo bar baz
	test "${rs}" = $'\n'
	test "${lst_cat}" = a,foo,bar,baz
	rec a=cat foo bar baz
	test "${rs}" = $'\036'
	test "${lst_cat}" = a,foo,bar,baz
)

log a= 'foo bar' '' baz bam keks dose
log b= '' '' ''
log c=
log d= 'this is the' end
log e=cat a b c d
test "$e" = $'foo bar\n\nbaz\nbam\nkeks\ndose\n\n\n\nthis is the\nend\n'

#
# lst:convert
#

log a=
test "${a}" = ''
IRS=$'\n' ORS=,: lst:convert a x
test "${x}" = ''
IRS=$'\n' ORS=,: lst:convert a a
test "${a}" = ''
log a= foo bar baz
test "${a}" = $'foo\nbar\nbaz\n'
IRS=$'\n' ORS=,: lst:convert a x
test "${x}" = 'foo,bar,baz,'
IRS=$'\n' ORS=,: lst:convert a a
test "${a}" = 'foo,bar,baz,'
log a= '' foo '' bar baz
test "${a}" = $'\nfoo\n\nbar\nbaz\n'
IRS=$'\n' ORS=,: lst:convert a x
test "${x}" = 'foo,bar,baz,'
IRS=$'\n' ORS=,: lst:convert a a
test "${a}" = 'foo,bar,baz,'
csv c= '' foo '' bar baz
test "${c}" = ',foo,,bar,baz,'
IRS=$',' ORS=$'\n': lst:convert c a
test "${a}" = $'\nfoo\n\nbar\nbaz\n'

#
# lst:cast
#

log a= foo $'bar\tender' baz
lst:cast log:a csv:b
test "${b}" = $'foo,bar\tender,baz,'
lst:cast csv:b log:c
test "${c}" = $'foo\nbar\tender\nbaz\n'
lst:cast csv:b rec:d
test "${d}" = $'foo\036bar\tender\036baz\036'
lst:cast rec:d csv:e
test "${e}" = $'foo,bar\tender,baz,'

rec a= $'text\nwith' $'line\nfeed' $'for the\nlulz'
test "${a}" = $'text\nwith\036line\nfeed\036for the\nlulz\036'
lst:cast rec:a csv:b
test "${b}" = $'text\nwith,line\nfeed,for the\nlulz,'
lst:cast csv:b log:c
test "${c}" = $'text\nwith\nline\nfeed\nfor the\nlulz\n'
lst:cast log:c rec:d
test "${d}" = $'text\036with\036line\036feed\036for the\036lulz\036'
lst:cast log:c csv:e
test "${e}" = $'text,with,line,feed,for the,lulz,'
lst:cast csv:e rec:e
test "${e}" = $'text\036with\036line\036feed\036for the\036lulz\036'

rec a= text with '' empty entries '' ''
test "$a" = $'text\036with\036\036empty\036entries\036\036\036'
lst:cast rec:a log:b
test "$b" = $'text\nwith\n\nempty\nentries\n\n\n'
lst:cast log:b rec:c
test "$c" = $'text\036with\036empty\036entries\036'
