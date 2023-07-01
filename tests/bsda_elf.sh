. ../src/bsda_elf.sh

prestate="$(x=0; set | grep -v _nextId=)"

! (bsda:elf:File file /dev/null/fail 2>&-)

bsda:elf:File file /boot/kernel/kernel
$file.fetch value ostype
ostype="$(sysctl -n kern.ostype)"
test "${value}" = "${ostype}"
$file.fetchEnc value ostype vis
test "${value}" = "${ostype}\000"
$file.delete

# Check for complete cleanup
unset file value ostype
poststate="$(unset prestate; x=0; set | grep -v _nextId=)"
test "$prestate" = "$poststate"
