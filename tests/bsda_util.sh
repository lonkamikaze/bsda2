. ../src/bsda_util.sh

f=x
bsda:util:map 'x y z 123.456 foo' a b c d e f
test "$a" = "x"
test "$b" = "y"
test "$c" = "z"
test "$d" = "123.456"
test -z "$f"

IFS=, bsda:util:map '1,2,3,4,5' a b c
test "$a" = "1"
test "$b" = "2"
test "$c" = "3"
test "$d" = "123.456"
test -z "$f"

IFS=: bsda:util:mapfun colonmap foo bar baz bam boom bang
colonmap a:b c:d:e f
test "$foo" = "a"
test "$bar" = "b"
test "$baz" = "c"
test "$bam" = "d"
test "$boom" = "e"
test "$bang" = "f"

colonmap yes no:maybe
test "$foo" = "yes"
test "$bar" = "no"
test "$baz" = "maybe"
test -z "$bam"
test -z "$boom"
test -z "$bang"

unset -f colonmap

bsda:util:join list , mondays are the worst
test "$list" = "mondays,are,the,worst"

bsda:util:split list ,
test "$list" = "mondays are the worst"

bsda:util:count cnt $list
test "$cnt" -eq 4

bsda:util:in foo a b c bam boom foo bar
bsda:util:in bam a b c bam boom foo bar
bsda:util:in foo foo a b c bam boom bar
bsda:util:in foo a b c bam boom bar foo
bsda:util:in foo foo a b c bam boom bar foo
! bsda:util:in fox a b c bam boom foo bar

bsda:util:ltrim bar "	    sasdkfj aijro kljk	20r	   "
test "${bar}" = "sasdkfj aijro kljk	20r	   "
bsda:util:rtrim bar "	    sasdkfj aijro kljk	20r	   "
test "${bar}" = "	    sasdkfj aijro kljk	20r"
bsda:util:trim bar "	    sasdkfj aijro kljk	20r	   "
echo "[${bar}]"
test "${bar}" = "sasdkfj aijro kljk	20r"
