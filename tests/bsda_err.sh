#
# Error/exit codes
#

# Setup caller tracing to simulate context
caller=caller
caller_unwind=
caller.delete() {
	caller_unwind="$1"$'\n'"${caller_unwind}"
}
unwind() {
	local IFS obj
	IFS=$'\n'
	for obj in $caller_unwind; do
		$obj.delete
	done
	caller_unwind=
}

test -z "${E_OK+1}"
test -z "${E_WARN+1}"
test -z "${E_SIGNAL+1}"
test -z "${E_FAIL+1}"

. ../src/bsda_err.sh

test -n "${E_OK+1}"
test -n "${E_WARN+1}"
test -n "${E_SIGNAL+1}"
test -n "${E_FAIL+1}"

test "$E_OK"     -eq 0
test "$E_WARN"   -eq 0
test "$E_SIGNAL" -eq 1
test "$E_FAIL"   -eq 2

bsda:err:ecs ecs
test "$ecs" = $'E_OK=0\nE_WARN=0\nE_SIGNAL=1\nE_FAIL=2'

test -z "${E_ALIAS_REF+1}"
test -z "${E_ALIAS_VAL+1}"
test -z "${E_CODE_SEQ1+1}"
test -z "${E_CODE_SEQ2+1}"

bsda:err:createECs E_ALIAS_REF=E_WARN E_ALIAS_VAL=23 E_CODE_SEQ1 E_CODE_SEQ2

test -n "${E_ALIAS_REF+1}"
test -n "${E_ALIAS_VAL+1}"
test -n "${E_CODE_SEQ1+1}"
test -n "${E_CODE_SEQ2+1}"

test "$E_ALIAS_REF" -eq "$E_WARN"
test "$E_ALIAS_VAL" -eq 23
test "$E_CODE_SEQ1" -eq 3
test "$E_CODE_SEQ2" -eq 4

bsda:err:ecs ecs
test "$ecs" = $'E_OK=0\nE_WARN=0\nE_SIGNAL=1\nE_FAIL=2\nE_ALIAS_REF=0\nE_ALIAS_VAL=23\nE_CODE_SEQ1=3\nE_CODE_SEQ2=4'

#
# Test behaviour without a context.
#

# bsda:err:panic() non-fatal

# Must not fail
(bsda:err:panic 0      raw  2>&-)
(bsda:err:panic E_OK   ok   2>&-)
(bsda:err:panic E_WARN warn 2>&-)

# Must output message on stderr
test "$(bsda:err:panic 0      raw  2>&1)" = raw
test "$(bsda:err:panic E_OK   ok   2>&1)" = ok
test "$(bsda:err:panic E_WARN warn 2>&1)" = warn

# Must not exit
(bsda:err:panic 0      raw  2>&-; exit 42); test $? -eq 42
(bsda:err:panic E_OK   ok   2>&-; exit 42); test $? -eq 42
(bsda:err:panic E_WARN warn 2>&-; exit 42); test $? -eq 42

# bsda:err:panic() fatal

# Must output message on stderr
test "$(bsda:err:panic 42          raw   2>&1)" = raw
test "$(bsda:err:panic E_CODE_SEQ1 seq   2>&1)" = seq
test "$(bsda:err:panic E_ALIAS_VAL alias 2>&1)" = alias

# Must exit
(bsda:err:panic 42          raw   2>&-; exit 0); test $? -eq 42
(bsda:err:panic E_CODE_SEQ1 seq   2>&-; exit 0); test $? -eq $E_CODE_SEQ1
(bsda:err:panic E_ALIAS_VAL alias 2>&-; exit 0); test $? -eq $E_ALIAS_VAL

# bsda:err:raise(), non-fatal

# Must not fail
(bsda:err:raise 0      raw  2>&-)
(bsda:err:raise E_OK   ok   2>&-)
(bsda:err:raise E_WARN warn 2>&-)

# Must output message on stderr
test "$(bsda:err:raise 0      raw  2>&1)" = raw
test "$(bsda:err:raise E_OK   ok   2>&1)" = ok
test "$(bsda:err:raise E_WARN warn 2>&1)" = warn

# Must not exit
(bsda:err:raise 0      raw  2>&-; exit 42); test $? -eq 42
(bsda:err:raise E_OK   ok   2>&-; exit 42); test $? -eq 42
(bsda:err:raise E_WARN warn 2>&-; exit 42); test $? -eq 42

# bsda:err:raise(), fatal

# Must output message on stderr
test "$(bsda:err:raise 42          raw   2>&1)" = raw
test "$(bsda:err:raise E_CODE_SEQ1 seq   2>&1)" = seq
test "$(bsda:err:raise E_ALIAS_VAL alias 2>&1)" = alias

# Must exit
(bsda:err:raise 42          raw   2>&-; exit 0); test $? -eq 42
(bsda:err:raise E_CODE_SEQ1 seq   2>&-; exit 0); test $? -eq $E_CODE_SEQ1
(bsda:err:raise E_ALIAS_VAL alias 2>&-; exit 0); test $? -eq $E_ALIAS_VAL

# bsda:err:get()

! (bsda:err:get e msg 2>&-)
test -z "$(bsda:err:get e msg 2>&-)"
test -n "$(bsda:err:get e msg 2>&1)"
(bsda:err:get e msg 2>&-; exit 0); test $? -eq $((E_FAIL))

# bsda:err:forward()

# Must always fail
! (bsda:err:forward 0      raw  2>&-)
! (bsda:err:forward E_OK   ok   2>&-)
! (bsda:err:forward E_WARN warn 2>&-)

# Must output a different message on stderr
test "$(bsda:err:forward 0           raw   2>&1)" != raw
test "$(bsda:err:forward E_OK        ok    2>&1)" != ok
test "$(bsda:err:forward E_WARN      warn  2>&1)" != warn
test "$(bsda:err:forward 42          raw   2>&1)" != raw
test "$(bsda:err:forward E_CODE_SEQ1 seq   2>&1)" != seq
test "$(bsda:err:forward E_ALIAS_VAL alias 2>&1)" != alias

# Must exit with E_FAIL
(bsda:err:forward 0           raw   2>&-; exit 0); test $? -eq $((E_FAIL))
(bsda:err:forward E_OK        ok    2>&-; exit 0); test $? -eq $((E_FAIL))
(bsda:err:forward E_WARN      warn  2>&-; exit 0); test $? -eq $((E_FAIL))
(bsda:err:forward 42          raw   2>&-; exit 0); test $? -eq $((E_FAIL))
(bsda:err:forward E_CODE_SEQ1 seq   2>&-; exit 0); test $? -eq $((E_FAIL))
(bsda:err:forward E_ALIAS_VAL alias 2>&-; exit 0); test $? -eq $((E_FAIL))

#
# Test behaviour with context.
#

# bsda:err:panic() non-fatal
bsda:err:collect

# Must not fail
(bsda:err:panic 0      raw  2>&-)
(bsda:err:panic E_OK   ok   2>&-)
(bsda:err:panic E_WARN warn 2>&-)

# Must output message on stderr
test "$(bsda:err:panic 0      raw  2>&1)" = raw
test "$(bsda:err:panic E_OK   ok   2>&1)" = ok
test "$(bsda:err:panic E_WARN warn 2>&1)" = warn

# Must not exit
(bsda:err:panic 0      raw  2>&-; exit 42); test $? -eq 42
(bsda:err:panic E_OK   ok   2>&-; exit 42); test $? -eq 42
(bsda:err:panic E_WARN warn 2>&-; exit 42); test $? -eq 42

# bsda:err:panic() fatal

# Must output message on stderr
test "$(bsda:err:panic 42          raw   2>&1)" = raw
test "$(bsda:err:panic E_CODE_SEQ1 seq   2>&1)" = seq
test "$(bsda:err:panic E_ALIAS_VAL alias 2>&1)" = alias

# Must exit
(bsda:err:panic 42          raw   2>&-; exit 0); test $? -eq 42
(bsda:err:panic E_CODE_SEQ1 seq   2>&-; exit 0); test $? -eq $E_CODE_SEQ1
(bsda:err:panic E_ALIAS_VAL alias 2>&-; exit 0); test $? -eq $E_ALIAS_VAL

! bsda:err:get
unwind

# bsda:err:raise()
bsda:err:collect

# Must not exit
(bsda:err:raise 0           raw;   exit 42); test $? -eq 42
(bsda:err:raise E_OK        ok;    exit 42); test $? -eq 42
(bsda:err:raise E_WARN      warn;  exit 42); test $? -eq 42
(bsda:err:raise 23          raw;   exit 42); test $? -eq 42
(bsda:err:raise E_CODE_SEQ1 seq;   exit 42); test $? -eq 42
(bsda:err:raise E_ALIAS_VAL alias; exit 42); test $? -eq 42

# Check issue sequence
bsda:err:raise 0           raw
bsda:err:raise E_OK        ok
bsda:err:raise E_WARN      warn
bsda:err:raise 23          raw
bsda:err:raise E_CODE_SEQ1 seq
bsda:err:raise E_ALIAS_VAL alias

bsda:err:get e msg
test "$e"   = 0
test "$msg" = raw
bsda:err:get e msg
test "$e"   = E_OK
test "$msg" = ok
bsda:err:get e msg
test "$e"   = E_WARN
test "$msg" = warn
bsda:err:get e msg
test "$e"   = 23
test "$msg" = raw
bsda:err:get e msg
test "$e"   = E_CODE_SEQ1
test "$msg" = seq
bsda:err:get e msg
test "$e"   = E_ALIAS_VAL
test "$msg" = alias
! bsda:err:get e msg
unwind

# bsda:err:forward() without parent context
bsda:err:collect

# Must not fail
(bsda:err:forward 0      raw  2>&-)
(bsda:err:forward E_OK   ok   2>&-)
(bsda:err:forward E_WARN warn 2>&-)

# Must output message on stderr
test "$(bsda:err:forward 0           raw   2>&1)" = raw
test "$(bsda:err:forward E_OK        ok    2>&1)" = ok
test "$(bsda:err:forward E_WARN      warn  2>&1)" = warn
test "$(bsda:err:forward 42          raw   2>&1)" = raw
test "$(bsda:err:forward E_CODE_SEQ1 seq   2>&1)" = seq
test "$(bsda:err:forward E_ALIAS_VAL alias 2>&1)" = alias

# Must not exit
(bsda:err:forward 0           raw   2>&-; exit 42); test $? -eq 42
(bsda:err:forward E_OK        ok    2>&-; exit 42); test $? -eq 42
(bsda:err:forward E_WARN      warn  2>&-; exit 42); test $? -eq 42

# Must exit
(bsda:err:forward 42          raw   2>&-; exit 0); test $? -eq 42
(bsda:err:forward E_CODE_SEQ1 seq   2>&-; exit 0); test $? -eq $((E_CODE_SEQ1))
(bsda:err:forward E_ALIAS_VAL alias 2>&-; exit 0); test $? -eq $((E_ALIAS_VAL))

! bsda:err:get e msg
unwind

# bsda:err:forward() with parent context
bsda:err:collect
bsda:err:collect

# Must not fail
(bsda:err:forward 0      raw  2>&-)
(bsda:err:forward E_OK   ok   2>&-)
(bsda:err:forward E_WARN warn 2>&-)

# Must not produce output
test -z "$(bsda:err:forward 0           raw   2>&1)"
test -z "$(bsda:err:forward E_OK        ok    2>&1)"
test -z "$(bsda:err:forward E_WARN      warn  2>&1)"
test -z "$(bsda:err:forward 42          raw   2>&1)"
test -z "$(bsda:err:forward E_CODE_SEQ1 seq   2>&1)"
test -z "$(bsda:err:forward E_ALIAS_VAL alias 2>&1)"

# Must not exit
(bsda:err:forward 0           raw  ; exit 42); test $? -eq 42
(bsda:err:forward E_OK        ok   ; exit 42); test $? -eq 42
(bsda:err:forward E_WARN      warn ; exit 42); test $? -eq 42
(bsda:err:forward 42          raw  ; exit 13); test $? -eq 13
(bsda:err:forward E_CODE_SEQ1 seq  ; exit 13); test $? -eq 13
(bsda:err:forward E_ALIAS_VAL alias; exit 13); test $? -eq 13

# Check issue sequence
bsda:err:forward 0           raw
bsda:err:forward E_OK        ok
bsda:err:forward E_WARN      warn
bsda:err:forward 42          raw
bsda:err:forward E_CODE_SEQ1 seq
bsda:err:forward E_ALIAS_VAL alias

! bsda:err:get e msg
bsda:err:get e msg
test "$e"   = 0
test "$msg" = raw
bsda:err:get e msg
test "$e"   = E_OK
test "$msg" = ok
bsda:err:get e msg
test "$e"   = E_WARN
test "$msg" = warn
bsda:err:get e msg
test "$e"   = 42
test "$msg" = raw
bsda:err:get e msg
test "$e"   = E_CODE_SEQ1
test "$msg" = seq
bsda:err:get e msg
test "$e"   = E_ALIAS_VAL
test "$msg" = alias
! bsda:err:get e msg
unwind

# bsda:err:collect

# Do not print on stdout
test -z "$(exec 2> /dev/null
	bsda:obj:fork
	bsda:err:collect
	unwind
)" #
test -z "$(exec 2> /dev/null
	bsda:obj:fork
	bsda:err:collect
	bsda:err:raise E_WARN warn
	unwind
)" #

# Do not affect exit
(exec 2> /dev/null
	bsda:obj:fork
	bsda:err:collect
	unwind
)
(exec 2> /dev/null
	bsda:obj:fork
	bsda:err:collect
	bsda:err:raise E_WARN warn
	unwind
)
(exec 2> /dev/null
	bsda:obj:fork
	bsda:err:collect
	bsda:err:collect
	bsda:err:raise E_WARN warn
	unwind
)

# Check for hints and warnings
run="$(exec 2>&1
	bsda:obj:fork
	bsda:err:collect
	unwind
)"
bsda:test:xmatch "$run" all:any 'bsda:err: HINT: *'
run="$(exec 2>&1
	bsda:obj:fork
	bsda:err:collect
	bsda:err:raise E_WARN warn
	bsda:err:raise E_WARN fail
	unwind
)"
bsda:test:xmatch "$run" all:all \
                 'bsda:err: HINT: *' \
                 'bsda:err: WARNING: *drop*' \
                 'warn' \
                 'fail'
run="$(exec 2>&1
	bsda:obj:fork
	bsda:err:collect
	bsda:err:collect
	bsda:err:raise E_WARN warn
	bsda:err:raise E_FAIL fail
	unwind
)"
bsda:test:xmatch "$run" all:all \
                 'bsda:err: HINT: *' \
                 'bsda:err: WARNING: *defer*' \
                 'bsda:err: WARNING: *drop*' \
                 'warn' \
                 'fail'
