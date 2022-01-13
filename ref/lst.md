	   __          __              __
	  / /\  ____  / /_      ____  / /\
	 / / / / __/\/ __/\    / __/\/  \/
	/ /_/ /_  /\/ /___/_  /_  /\/ / /\
	\__/\/___/ /\__/\/_/\/___/ /_/_/ /
	 \__/\____/  \__/ \_/\____/\____/
	
	 [ STANDALONE LIBRARY est. 2021 ]

LST.SH - Portable Array Library for Shell-Scripts
=================================================

LST.sh is a simple portable shell array library. It provides a way
of treating a string as an array by splitting it using a Record Separator
character.

Arrays can be accessed by index:

```sh
. ./lst.sh

rec a= 'First entry' $'Second\nentry' 'Third entry$'

rec a[1]      # prints: First entry
rec a[-1]     # prints: Third entry$
rec a[2] entry
test "${entry}" = $'Second\nentry' # succeeds
```

Entries can be appended or prepended:

```sh
rec a.push_back  'Final entry'
rec a.push_front 'Preliminary entry'
ORS=\| rec a  # prints:
              # Preliminary entry|First entry|Second
              # entry|Third entry$|Final entry
```

Entries can be iterated over by index:

```sh
i=0
while rec a[i+=1] entry; do
    printf '%2d: <%s>\n' $i "${entry}"
done          # prints:
              #  1: <Preliminary entry>
              #  2: <First entry>
              #  3: <Second
              # entry>
              #  4: <Third entry$>
              #  5: <Final entry>
```

Or by regular variable expansion:

```sh
rec a.set_ifs
for entry in $a; do
    echo "<${entry}>"
done          # prints:
              # <Preliminary entry>
              # <First entry>
              # <Second
              # entry>
              # <Third entry$>
              # <Final entry>
```


The array functionality is accessed by using the function `lst()`
with the variable `RS` set to the value of the separator character.
The first argument to `lst()` is always the name of an array followed
by an operator.

Providing the Record Separator `RS` to `lst()`
----------------------------------------------

There are three ways providing the Record Separator to the `lst()`
function:

1. Setting it globally:
   `RS='|'`
2. Providing it constrained to a single invocation:
   `RS='|' lst ...`
3. Or defining a wrapper function that calls `lst()`:
   `array() { RS='|' lst "$@"; }`

The first way has most merit when a single Record Separator is the
correct choice for an entire shell script. The third method provides
an opportunity to give more semantic meaning to calls of `lst()`.
Three `lst()` wrappers are provided:

- `log()`
  Uses the Line Feed character as an entry separator, this is subject
  to limitations, detailed in the next section.
- `rec()`
  Uses the ASCII Record Separator character (RS) as a Record Separator
  (see `ascii(7)`). Other good candidates from this character group
  would be the Field Separator (FS), the Group Separator (GS)
  and the Unit Separator (US).
- `csv()`
  Uses the comma character `,` to separate array entries. This is
  akin to using other characters like slashes, colons, semicolons
  or pipes when they happen to not be used as characters within the
  array entries.

The `rec()` function is a sane default providing full functionality
using a character that is unlikely to occur within non-binary data.

### White Space Record Separators

Using White Space characters such as Space, the Line Feed or Horizontal
Tab characters, affects the functionality of `lst()` in conjunction with
empty array entries.
This is due to some methods internally using Field Splitting, which
is subject to special rules when the Input Field Separator is set
to White Space character. See the White Space Splitting (Field Splitting)
section of `sh(1)`.

The Method/Function table column WS RS in the Operators and Methods
section documents which methods/functions are affected by this.
The source code documentation of the affected methods/functions provides
details on the specific effects.

If the use case does not make use of empty array entries, all functions
and methods can be used without limitations.

### Array Conversions

There are two functions to convert arrays from one Record Separator
to another. The difference is in the delivery of the Input and Output
Record Separators.

The `lst:convert()` function allows providing arbitrary Separators:

```sh
# converts `log src` to `rec dst`
IRS=$'\n' ORS=$'\036' lst:convert src dst

# converts `log a` to `rec a`
IRS=$'\n' ORS=$'\036' lst:convert a a
```

The `lst:cast()` function uses `lst()` wrapper functions to determine
the Record Separators:

```sh
# converts `log src` to `rec dst`
lst:cast log:src rec:dst

# converts `log a` to `rec a`
lst:cast log:a rec:a
```

Operators and Methods
---------------------

The following operators are available (`a` is the name of an array,
`i` is an index value / arithmetic expression, `m` is the name of
a method):

| Operator | Action                                                          |
|----------|-----------------------------------------------------------------|
| `a[i].m` | Call array subscript method                                     |
| `a[i]=`  | Array subscript assign (equivalent to `a[i].set`)               |
| `a[i]`   | Array subscript access (equivalent to `a[i].get`)               |
| `a.m`    | Call array method                                               |
| `a=cat`  | Create by concatenating arrays (equivalent to `lst:cat a`)      |
| `a=`     | Array create/reset and assign values                            |
| `a`      | Print array (equivalent to `a.print`)                           |

Supported methods and functions are listed in the table below.

The Complexity column is based on the number of shell operations,
so even operations like field splitting that clearly have a size
dependent cost are considered constant size. The variable `n` refers
to the size of the array, the variable `#` to the number of arguments
provided to the function/method call.

The WS RS column lists which functions/methods are subject to limitations
if the Record Separator is a White Space character.

| Method/Function  | Description                                             | Complexity | WS RS   |
|------------------|---------------------------------------------------------|------------|---------|
| `a[i].get`       | Read a single indexed entry                             | O(1)       | Limited |
| `a[i].set`       | Overwrite a single indexed entry                        | O(n)       | Limited |
| `a[i].rm`        | Remove an indexed array entry                           | O(n)       | Limited |
| `a.resize`       | Change the size of the array                            | O(n)       | Limited |
| `a.push_front`   | Prepend values                                          | O(#)       |         |
| `a.push_back`    | Append values                                           | O(#)       |         |
| `a.peek_front`   | Read first value                                        | O(1)       |         |
| `a.peek_back`    | Read last value                                         | O(1)       |         |
| `a.pop_front`    | Read first value and remove it                          | O(#)       |         |
| `a.pop_back`     | Read last value and remove it                           | O(#)       |         |
| `a.rm_first`     | Remove first match with the given value                 | O(#)       |         |
| `a.rm_last`      | Remove last match with the given value                  | O(#)       |         |
| `a.count`        | Provide the number of entries                           | O(1)       | Limited |
| `a.contains`     | Return whether the given value is in the array          | O(1)       |         |
| `a.contains_all` | Return whether all the given values are in the array    | O(#)       |         |
| `a.contains_any` | Return whether any of the given values are in the array | O(#)       |         |
| `a.merge`        | Concatenate all the given arrays                        | O(1)       |         |
| `a.print`        | Print array `ORS` separated                             | O(1)       | Limited |
| `a.printf`       | Print array with custom formatting                      | O(1)       | Limited |
| `a.set_irs`      | Set the Input Record Separator (`IRS`) to `RS`          | O(1)       |         |
| `a.set_ors`      | Set the Output Record Separator (`ORS`) to `RS`         | O(1)       |         |
| `a.set_ifs`      | Set the shell Input Field Separator (`IFS`) to `RS`     | O(1)       |         |
| `lst:cat`        | Concatenate arrays                                      | O(1)       |         |
| `lst:convert`    | Convert array Record Separator `IRS` to `ORS`           | O(1)       | Limited |
| `lst:cast`       | Convert array Record Separator based on lst() wrappers  | O(1)       | Limited |
