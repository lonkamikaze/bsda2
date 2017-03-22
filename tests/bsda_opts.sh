. ../src/bsda_opts.sh
. ../src/bsda_test.sh

# Create empty object
bsda:opts:Options opts
$opts.getopt; test $? -eq 2
$opts.usage; test $? -eq 2
$opts.delete

# Fail with incomplete tuples
! bsda:opts:Options opts TEST
! bsda:opts:Options opts TEST -t
! bsda:opts:Options opts TEST -t --test
# Create object
bsda:opts:Options opts TEST -t --test "Test desc"
$opt.delete
# Fail with incomplete tuples
! bsda:opts:Options opts \
TEST -t --test "Test desc" \
NEXT
! bsda:opts:Options opts \
TEST -t --test "Test desc" \
NEXT -n
! bsda:opts:Options opts \
TEST -t --test "Test desc" \
NEXT -n --next
# Create a two options list
bsda:opts:Options opts \
TEST -t --test "Test desc" \
NEXT -n --next "Next desc"

# Test if all the information is contained
$opts.usage str "%s,%s,%s\n"
bsda:test:match '-t,--test,Test desc\n-n,--next,Next desc\n' "$str" 

# Test appending incomplete tuples
! $opts.append FOO
! $opts.append FOO -f
! $opts.append FOO -f --foo
# Append complete tuple
$opts.append FOO -f --foo "Foo desc"

# Check object completeness
$opts.usage str "%s,%s,%s\n"
bsda:test:match '-t,--test,Test desc\n-n,--next,Next desc\n-f,--foo,Foo desc\n' "$str" 

# Fail with more incomplete tuples
! $opts.append BAR -b --bar "Bar desc"  XXX
! $opts.append BAR -b --bar "Bar desc"  XXX -x
! $opts.append BAR -b --bar "Bar desc"  XXX -x --xxx
# Append two options
$opts.append BAR -b --bar "Bar desc"  XXX -x --xxx "Xxx desc"

# Check object completeness
$opts.usage str "%s,%s,%s\n"
bsda:test:match '-t,--test,Test desc\n-n,--next,Next desc\n-f,--foo,Foo desc\n-b,--bar,Bar desc\n-x,--xxx,Xxx desc\n' "$str" 

# Append an option with an argument
$opts.append ARG -a* --arg "Arg desc"

# Check object completeness
$opts.usage str "%s,%s,%s\n"
bsda:test:match '-t,--test,Test desc\n-n,--next,Next desc\n-f,--foo,Foo desc\n-b,--bar,Bar desc\n-x,--xxx,Xxx desc\n-a\*,--arg,Arg desc\n' "$str" 

# Check matching stuff
$opts.getopt opt -x
test "$opt" = XXX
$opts.getopt opt --test
test "$opt" = TEST
$opts.getopt opt -nt
test "$opt" = OPT_SPLIT
$opts.getopt opt -ntf
test "$opt" = OPT_SPLIT
$opts.getopt opt -a
test "$opt" = ARG
$opts.getopt opt -afoobar
test "$opt" = ARG
$opts.getopt opt -y
test "$opt" = OPT_UNKNOWN
$opts.getopt opt --yes
test "$opt" = OPT_UNKNOWN
! $opts.getopt opt ./test
test "$opt" = OPT_NOOPT

# Clear up
$opts.delete

# Create a Flags instance
bsda:opts:Flags flags
$flags.add FOO
$flags.add BAR
$flags.add FOO
$flags.add BAZ

# Check flags
$flags.check FOO -ne 0
$flags.check BAR -ne 0
$flags.check BAZ -ne 0
! $flags.check XXX -ne 0
! $flags.check FOO -eq 0
! $flags.check BAR -eq 0
! $flags.check BAZ -eq 0
$flags.check XXX -eq 0
! $flags.check FOO -eq 1
$flags.check BAR -eq 1
$flags.check BAZ -eq 1
! $flags.check XXX -eq 1
$flags.check FOO -eq 2
! $flags.check BAR -eq 2
! $flags.check BAZ -eq 2
! $flags.check XXX -eq 2

# Clear up
$flags.delete
