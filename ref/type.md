	   __                      __
	  / /_______  ___     ____/ /
	 / __/ / /  \/ _ \   / __/  \
	/ /_/ / / / / ___/__/_  / / /
	\__/\  / __/\__/ /_/___/_/_/
	____/ /_/
	\____/    STANDALONE LIBRARY est. 2020

TYPE.SH - Simple Type Match/Cast for Shell-Scripts
==================================================

This standalone library provides rudimentary type checking/casting
functionality, entirely relying on shell builtins.

Types
-----

As far as the shell is concerned the only type is the character string.
It can handle integer arithmetic and comparison, so there is a notion
of integers. However even integers are stored in strings.

The library adds a set of types with more constraints:

| Type     | Description      | Matches (regex, case insensitive)          |
|----------|------------------|--------------------------------------------|
| uint     | unsigned integer | `^(0x[0-9a-f]+|[1-9][0-9]*|0[0-7]*)$`      |
| int      | integer          | `^[-+]?(0x[0-9a-f]+|[1-9][0-9]*|0[0-7]*)$` |
| bool     | boolean          | `^(0|1|yes|no|true|false)`                 |
| empty    | empty string     | `^$`                                       |
| argname  | argument number  | `^[0-9]$`                                  |
| varname  | variable name    | `^([a-z]|[a-z_][a-z0-9_]+)$`               |
| funcname | function name    | `^[0-9]*[][a-z_.:][][a-z0-9_.:]*$`         |

Conformity to a type can be checked using the match functions:

| Function                | Cost | Complexity                   |
|-------------------------|------|------------------------------|
| `type:match:empty()`    | O(1) | single `test` call           |
| `type:match:bool()`     | O(1) | single glob pattern match    |
| `type:match:uint()`     | O(n) | recursive glob pattern match |
| `type:match:int()`      | O(n) | recursive glob pattern match |
| `type:match:argname()`  | O(1) | single glob pattern match    |
| `type:match:varname()`  | O(n) | recursive glob pattern match |
| `type:match:funcname()` | O(n) | recursive glob pattern match |

The `type:match()` function allows checking whether a value matches
one of a set of types:

```
if ! type:match empty,bool "$1"; then
	…
fi
```

Type Detection
--------------

The `type:which()` function provides provides the name of the first
matched type from a list of given types.

```
if ! type:which type empty,bool,uint,int,varname "$1"; then
	echo "invalid value: $1" >&2
	return 1
fi
case "$type" in
empty)
	echo "empty value" >&2
	return 1
;;
bool)
	…
;;
…
esac
```

Type Casting
------------

The `type:cast[int]()` function assigns matching inputs as decimal
integer values:

```
type:cast[int] x empty,bool
echo "$x" # 0
type:cast[int] x empty,bool YES
echo "$x" # 1
type:cast[int] x empty,bool no
echo "$x" # 0
type:cast[int] x empty,bool True
echo "$x" # 1
```

Only the following types can be cast to `int`:

- `empty`
- `bool`
- `uint`
- `int`

The conversion is done for the first matching type. Independent of
the matched type, for a given value the assigned value is always the
same. E.g. 1 is a valid bool, int and uint and the assigned value for all
three is 1. Thus the order of the given types does not affect the
outcome of the type conversion.

The return value of type:cast[int] functions is the same as that
of type:match functions, so the same uses for control flow are possible:

```
if ! type:cast[int] verbose bool,int "$VERBOSITY"; then
	echo "Invalid VERBOSITY level, assume 0!" >&2
	verbose=0
fi
```

Individual cast functions can be called directly:

```
x=1
type:cast[int]:empty x || type:cast[int]:bool x
echo "$x" # 0
type:cast[int]:empty x YES || type:cast[int]:bool x YES
echo "$x" # 1
type:cast[int]:empty x no || type:cast[int]:bool x no
echo "$x" # 0
type:cast[int]:empty x True || type:cast[int]:bool x True
echo "$x" # 1
```

If no type matches, the destination variable remains unchanged:

```
x=nope
type:cast[int] x bool,int NaN
echo "$x" # nope
```
