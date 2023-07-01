. ../src/compat.sh

# Try setvar/getvar
setvar
setvar x 1337 && test "$x" = 1337
getvar
getvar y x && test "$y" = "$x"
test "$(getvar '' x)" = 1337
