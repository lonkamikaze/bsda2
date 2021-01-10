BSDA:ERR - Error Handling for BSDA:OBJ
======================================

`bsda:err` is an error handling library written for use with the
[bsda:obj](bsda_obj.md) framework.

The workflow of `bsda:err` is very similar to the try/throw/catch
exceptions workflow known from other languages. However, some fundamental
differences exist, thus all facilities have been named differently
in order to curb expectations of conforming to the familiar model.

The following table lists the  well known language mechanisms and 
their library counterparts:

| Mechanism | Substitution                          |
|-----------|---------------------------------------|
| `try`     | `bsda:err:collect`                    |
| `throw`   | `bsda:err:raise` / `bsda:err:forward` |
| `catch`   | `bsda:err:get`                        |

Issues
------

This error handling framework is based around the concept of issues.
An issue is a pair consisting of an error/exit code and a message.
The error/exit code may be an integral value, but it is usually
a predefined symbol. The following error/exit codes are predefined:

| Symbol   | Value | Meaning                                |
|----------|-------|----------------------------------------|
| E_OK     | 0     | No error                               |
| E_WARN   | 0     | Warning, non-fatal even when unhandled |
| E_SIGNAL | 1     | Interrupted by signal                  |
| E_FAIL   | 2     | Application logic failure              |

The bsda:err:createECs() function can be used to create additional
application specific error/exit codes.

Reporting and Handling Errors/Warnings
--------------------------------------

An issue can be created using the bsda:err:raise() function. The
default behaviour is to print the given message and exit with the
given error/exit code if it is non-zero.

The caller can override this behaviour by calling the bsda:err:collect()
function. This is the expected use case, the default behaviour is
a fallback for the case that issues are not handled by the application.

To force exit on an issue, even when the caller handles issues,
the bsda:err:panic() function can be used. This is only appropriate
for errors that indicate a flaw in the programming logic.

If the caller opts in to collecting issues these must be handled
before the caller scope ends. Otherwise all issue messages and a
couple of hints and warnings are printed on stderr.

Handling issues is done by calling bsda:err:get() until all issues
have been handled:

```sh
local e msg
bsda:err:collect
… code potentially raising issues …
while bsda:err:get e msg; do
	… handle errors/warnings …
done
```

Errors usually should be matched using the error/exit code:

```sh
while bsda:err:get e msg; do
	case "$e" in
	E_APP_ERROR)
		… handle …
	;;
	E_FAIL)
		# unrecoverable error
		bsda:err:panic "$e" "$msg"
	;;
	*)
		# forward to caller
		bsda:err:forward "$e" "$msg"
	;;
	esac
done
```

The bsda:err:forward() function acts like bsda:err:raise(), except
that it raises the issue in the parent context, passing on the
responsibility of handling the issue.
