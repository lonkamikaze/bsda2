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
test $'-t,--test,Test desc\n-n,--next,Next desc\n' = "$str"

# Test appending incomplete tuples
! $opts.append FOO
! $opts.append FOO -f
! $opts.append FOO -f --foo
# Append complete tuple
$opts.append FOO -f --foo "Foo desc"

# Check object completeness
$opts.usage str "%s,%s,%s\n"
test $'-t,--test,Test desc\n-n,--next,Next desc\n-f,--foo,Foo desc\n' = "$str"

# Fail with more incomplete tuples
! $opts.append BAR -b --bar "Bar desc"  XXX
! $opts.append BAR -b --bar "Bar desc"  XXX -x
! $opts.append BAR -b --bar "Bar desc"  XXX -x --xxx
# Append two options
$opts.append BAR -b --bar "Bar desc"  XXX -x --xxx "Xxx desc"

# Check object completeness
$opts.usage str "%s,%s,%s\n"
test $'-t,--test,Test desc\n-n,--next,Next desc\n-f,--foo,Foo desc\n-b,--bar,Bar desc\n-x,--xxx,Xxx desc\n' = "$str"

# Append an option with an argument
$opts.append ARG -a* --arg "Arg desc"

# Check object completeness
$opts.usage str "%s,%s,%s\n"
test $'-t,--test,Test desc\n-n,--next,Next desc\n-f,--foo,Foo desc\n-b,--bar,Bar desc\n-x,--xxx,Xxx desc\n-a*,--arg,Arg desc\n' = "$str"

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

# Check Flags initialisation from environment
unset FOO BAR BAZ
FOO=2
BAR=1
BAZ=1

# Do not use environment
bsda:opts:Flags flags
$flags.check FOO -eq 0
$flags.check BAR -eq 0
$flags.check BAZ -eq 0
$flags.delete

# Use environment, but variables are not available
bsda:opts:Flags flags FOO BAR BAZ
$flags.check FOO -eq 0
$flags.check BAR -eq 0
$flags.check BAZ -eq 0
$flags.delete

# Add variables to environment
export FOO BAR BAZ

# Do not use environment
bsda:opts:Flags flags
$flags.check FOO -eq 0
$flags.check BAR -eq 0
$flags.check BAZ -eq 0
$flags.delete

# Use environment
bsda:opts:Flags flags FOO BAR BAZ
$flags.check FOO -eq 2
$flags.check BAR -eq 1
$flags.check BAZ -eq 1
$flags.delete

# Ignore invalid values
BAR=-1
BAZ=firecracker
bsda:opts:Flags flags FOO BAR BAZ
$flags.check FOO -eq 2
$flags.check BAR -eq 0
$flags.check BAZ -eq 0
$flags.delete

# Assign regardless of env
bsda:opts:Flags flags FOO=3 BAR=4 BAZ=5
$flags.check FOO -eq 3
$flags.check BAR -eq 4
$flags.check BAZ -eq 5
$flags.delete

# Assign regardless of env, ignoring invalid values
BAR=1
BAZ=1
bsda:opts:Flags flags FOO=3 BAR=-1 BAZ=firecracker
$flags.check FOO -eq 3
$flags.check BAR -eq 0
$flags.check BAZ -eq 0
$flags.delete

# Assign default values, env has higher priority
bsda:opts:Flags flags FOO?=3 BAR?=4 BAZ?=5
$flags.check FOO -eq 2
$flags.check BAR -eq 1
$flags.check BAZ -eq 1
$flags.delete

# Assign default values, env has higher priority
unset BAR  # not in env, select default
BAZ=       # empty string > default
bsda:opts:Flags flags FOO?=3 BAR?=4 BAZ?=5
$flags.check FOO -eq 2
$flags.check BAR -eq 4
$flags.check BAZ -eq 0
$flags.delete

# Test boolean values
unset A B C D E F G H I J K L M N O
bsda:opts:Flags flags A= B=0 C=no D=NO E=No F=false G=FALSE H=False \
                      I=1 J=yes K=YES L=Yes M=true N=TRUE O=True
$flags.check A -eq 0
$flags.check B -eq 0
$flags.check C -eq 0
$flags.check D -eq 0
$flags.check E -eq 0
$flags.check F -eq 0
$flags.check G -eq 0
$flags.check H -eq 0
$flags.check I -eq 1
$flags.check J -eq 1
$flags.check K -eq 1
$flags.check L -eq 1
$flags.check M -eq 1
$flags.check N -eq 1
$flags.check O -eq 1
$flags.delete

# Test boolean default values
bsda:opts:Flags flags A?= B?=0 C?=no D?=NO E?=No F?=false G?=FALSE H?=False \
                      I?=1 J?=yes K?=YES L?=Yes M?=true N?=TRUE O?=True
$flags.check A -eq 0
$flags.check B -eq 0
$flags.check C -eq 0
$flags.check D -eq 0
$flags.check E -eq 0
$flags.check F -eq 0
$flags.check G -eq 0
$flags.check H -eq 0
$flags.check I -eq 1
$flags.check J -eq 1
$flags.check K -eq 1
$flags.check L -eq 1
$flags.check M -eq 1
$flags.check N -eq 1
$flags.check O -eq 1
$flags.delete

# Set boolean values from environment
export A=1 B=yes C=YES D=Yes E=true F=TRUE G=True \
       H= I=0 J=no K=NO L=No M=false N=FALSE O=False
bsda:opts:Flags flags A B C D E F G H I J K L M N O
$flags.check A -eq 1
$flags.check B -eq 1
$flags.check C -eq 1
$flags.check D -eq 1
$flags.check E -eq 1
$flags.check F -eq 1
$flags.check G -eq 1
$flags.check H -eq 0
$flags.check I -eq 0
$flags.check J -eq 0
$flags.check K -eq 0
$flags.check L -eq 0
$flags.check M -eq 0
$flags.check N -eq 0
$flags.check O -eq 0
$flags.delete

# Override boolean defaults from environment
bsda:opts:Flags flags A?= B?=0 C?=no D?=NO E?=No F?=false G?=FALSE H?=False \
                      I?=1 J?=yes K?=YES L?=Yes M?=true N?=TRUE O?=True
$flags.check A -eq 1
$flags.check B -eq 1
$flags.check C -eq 1
$flags.check D -eq 1
$flags.check E -eq 1
$flags.check F -eq 1
$flags.check G -eq 1
$flags.check H -eq 0
$flags.check I -eq 0
$flags.check J -eq 0
$flags.check K -eq 0
$flags.check L -eq 0
$flags.check M -eq 0
$flags.check N -eq 0
$flags.check O -eq 0
$flags.delete

# Set boolean values regardless of environment
bsda:opts:Flags flags A= B=0 C=no D=NO E=No F=false G=FALSE H=False \
                      I=1 J=yes K=YES L=Yes M=true N=TRUE O=True
$flags.check A -eq 0
$flags.check B -eq 0
$flags.check C -eq 0
$flags.check D -eq 0
$flags.check E -eq 0
$flags.check F -eq 0
$flags.check G -eq 0
$flags.check H -eq 0
$flags.check I -eq 1
$flags.check J -eq 1
$flags.check K -eq 1
$flags.check L -eq 1
$flags.check M -eq 1
$flags.check N -eq 1
$flags.check O -eq 1
$flags.delete
