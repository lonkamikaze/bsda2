	    ______ ______ ___    _____      _____  ____________
	   /  _  //   __//   \  /  _  / __ /  _  \/  _  /___  /
	  /  ___/ \  \  /  /  \/     / /_//  //  /  ___/   / /
	 /  __  /_/   \/  /   /  //  /__ /  //  /  __  /  / /
	/______/______/______/__//__//_/ \_____/______/  / /
	                             ___________________/ /
	WORSE THAN PERL SINCE 2009  /____________________/

BSDA:OBJ - Real World OO for Shell-Scripting
============================================

The `bsda:obj` framework offers you some common OO-foo for shell scripting
like classes, encapsulation, polymorphism with and without inheritance,
method overloading, introspection, serialisation, automatic creation
of getters and setters and garbage collection upon process termination.

`bsda:obj` provides a higher level of abstraction and code reuse without
sacrificing the flexibility and versatility of shell scripting.

HISTORY
-------

This framework was originally developed for the now obsolete `pkg_upgrade`
from the first gen _BSD Adminstration Scripts_. Back in the day the shell
based `portmaster` had pretty much replaced the perl based `portupgrade` as
the goto ports management tool. And I was of the opinion that anything
but a shell script would not gain any user acceptance.

So back in 2009 at the [GPN8 hacker conference][1], I started working on
this.  I presented it at the EuroBSDCon 2010 with [a talk and a
paper][2]. 

Then the whole endeavour came to rest as I was busy [building race
cars][3], which mostly resulted in [C code][4].

Finally, during the [31C3][5] I rewrote `pkg_libchk` on a whim and revived
`bsda:obj` along with it.

  [1]: https://entropia.de/GPN8
  [2]: http://2010.eurobsdcon.org/presentations-schedule/paper-detail-view/?tx_ptconfmgm_controller_detail_paper[uid]=17&tx_ptconfmgm_controller_detail_paper[pid]=299
  [3]: http://highspeed-karlsruhe.de/
  [4]: http://hsk.sf.net/
  [5]: https://events.ccc.de/congress/2014/

* * *

TABLE OF CONTENTS
-----------------

1. [DEFINING CLASSES](#1-defining-classes)
   1. [Basic Class Creation](#1-1-basic-class-creation)
   2. [Aggregations](#1-2-aggregations)
   3. [Access Scope](#1-3-access-scope)
2. [IMPLEMENTING METHODS](#2-implementing-methods)
   1. [Regular Methods](#2-1-regular-methods)
      1. [Accessing Attributes](#2-1-1-accessing-attributes)
      2. [Returning Data](#2-1-2-returning-data)
      3. [Temporary Objects](#2-1-3-temporary-objects)
   2. [Special Methods](#2-2-special-methods)
3. [CONSTRUCTOR](#3-constructor)
4. [DESTRUCTOR](#4-destructor)
5. [COPY](#5-copy)
6. [GET](#6-get)
7. [SET](#7-set)
8. [TYPE CHECKS](#8-type-checks)
    1. [Object Type Checks](#8-1-object-type-checks)
    2. [Primitive Type Checks](#8-2-primitive-type-checks)
9. [SERIALISE](#9-serialise)
    1. [Serialising](#9-1-serialising)
    2. [Deserialising](#9-2-deserialising)
    3. [Filtering](#9-3-filtering)
    4. [Dumping](#9-4-dumping)
10. [REFLECTION & REFACTORING](#10-reflection-refactoring)
    1. [Attributes](#10-1-attributes)
    2. [Methods](#10-2-methods)
11. [FORKING PROCESSES](#11-forking-processes)
    1. [Creating Child Processes](#11-1-creating-child-processes)
    2. [Detaching from the Execution Context](#11-2-detaching-from-the-execution-context)
12. [GARBAGE COLLECTION](#12-garbage-collection)
13. [FILE DESCRIPTORS](#13-file-descriptors)
14. [COMPATIBILITY](#14-compatibility)
    1. [POSIX](#14-1-posix)
    2. [bash - local](#14-2-bash-local)
    3. [bash - setvar](#14-3-bash-setvar)
    4. [bash - Command Substitution Variable Scope](#14-4-bash-command-substitution-variable-scope)
    5. [bash - alias](#14-5-bash-alias)



## 1. DEFINING CLASSES

This section describes the creation of classes.

* **NOTE**
  The details of creating classes are listed in front of the
  `bsda:obj:createClass()` function.

Creating a class consists of two steps, the first step is to call
the `bsda:obj:createClass()` function, the second one is to implement the
methods. This section describes the first step.

In order to create classes this framework has to be loaded:

~~~ bash
. ./bsda_obj.sh
~~~

### 1.1. Basic Class Creation

Creating a class does not require more than a class name:

~~~ bash
bsda:obj:createClass MyClass
~~~

After the previous line the class can be used to create objects,
and all the reserved methods are available:

~~~ bash
MyClass myObject
$myObject.delete
~~~

It is possible to create classes as simple data structures, that do not
require the programmer to write any methods to function:

~~~ bash
bsda:obj:createClass MyPoint2D \
	w:name \
	w:x \
	w:y
~~~

Instances of the MyPoint2D class now offer the `getName()` and `setName()`,
`getX()` and `setX()`, `getY()` and `setY()` methods:

~~~ bash
MyPoint2D point
$point.setName "upper left corner"
$point.setX 0
$point.setY 0
~~~

It might be a good idea to add an init method to the class in order to
assign values:

~~~ bash
bsda:obj:createClass MyConstPoint2D \
	i:init \
	r:name \
	r:x \
	r:y

MyConstPoint2D.init() {
	[ … assign values, maybe even check types … ]
}
~~~

* **NOTE**
  The init method can have an arbitrary name.

Note that the attributes were now created with `r:`, this means they only
have get methods, no set methods. All the values are now assigned during
object creation by the init method:

~~~ bash
MyConstPoint2D corner "upper right corner" 640 0
~~~

### 1.2. Aggregations

Aggregations are attributes with special properties:

~~~ bash
bsda:obj:createClass Triangle2D \
	a:A:MyPoint2D \
	a:B:MyPoint2D \
	a:C:MyPoint2D \
	i:init

Triangle2D.init() {
	# Create the points making up a triangle.
	MyPoint2D ${this}A
	MyPoint2D ${this}B
	MyPoint2D ${this}C
}

Triangle2D tri
$tri.A point
$point.setX 13
$point.setY 37
…
$tri.delete # Delete triangle, including all the points.
~~~

Aggregations are a weak form of composition, the creation of aggregated
objects has to be done explicitly, but their lifetime is bound to
the aggregating object. I.e. they are deleted implicitly.

### 1.3. Access Scope

You might want to limit access to certain methods, for this you can
add the scope operators private and public. If no scope operator is
given, public is assumed.

- `public`: This scope allows access from anywhere
- `private`: Only instances of the same class have access

The scope operator is added after the identifier type prefix. Only
prefixes that declare methods can have a scope operator.

~~~ bash
bsda:obj:createClass myNs:Person \
	i:private:init \
	w:private:familyName \
	w:private:firstName
~~~

* **NOTE**
  The constructor is always public. Declaring a scope for an init method
  only affects direct calls of the method.

Now the getters and setters for both `familyName` and `firstName` are private.
It is possible to widen the scope of a method by redeclaring it.

~~~ bash
bsda:obj:createClass myNs:Person \
	i:private:init \
	w:private:familyName \
	x:public:getFamilyName \
	w:private:firstName \
	x:public:getFirstName
~~~



## 2. IMPLEMENTING METHODS

All that remains to be done to get a functional class after defining it,
is to implement the required methods.
Methods are really just functions that the constructor
creates a wrapper for that forwards the object reference to them.

### 2.1. Regular Methods

The following special variables are available:

| Variable    | Description
|-------------|--------------------------------------------------------------
| `this`      | A reference to the current object
| `class`     | The name of the class this object is an instance of
| `caller`    | Provides access to methods to manipulate the caller context

The following methods are offered by the caller:

| Method      | Description
|-------------|--------------------------------------------------------------
| `setvar`    | Sets a variable in the caller context
| `delete`    | Deletes the given objects when returning to the caller
| `getObject` | Returns a reference to the calling object
| `getClass`  | Returns the name of the calling class

The following variable names may not be used in a method:

- `_return`
- `_var`

A method must always be named `<class>.<method>`. So a valid implementation
for a method named `bar` and a class named `foo` would look like this:

~~~ bash
foo.bar() {
}
~~~

The object reference is always available in the variable `this`, which
performs the same function as `self` in python or `this` in Java.

#### 2.1.1. Accessing Attributes

Attributes are resolved as `<objectId><attribute>`, the following example
shows how to read an attribute, manipulate it and write the new value.

~~~ bash
foo.bar() {
	local count
	# Get counter value.
	getvar count ${this}count
	# Increase counter value copy.
	count=$((count + 1))
	# Store the counter value.
	setvar ${this}count $count
}
~~~

The following example does the same with getters and setters. Getters and
setters are documented in sections [6](#6-get) and [7](#7-set).

~~~ bash
foo.bar() {
	local count
	# Get counter value.
	$this.getCount count
	# Increase counter value copy.
	count=$((count + 1))
	# Store the counter value.
	$this.setCount "$count"
}
~~~

#### 2.1.2. Returning Data

To return data into the calling context `$caller.setvar` is used. It
provides the possibility to overwrite variables in the caller context
even when there is a local variable using the same name.
Note that it has to be assumed that the names of variables used within
a method are unknown to the caller, so this can always be the case.

The name of the variable to store something in the caller context is
normally given by the caller itself as a parameter to the method call.

The following method illustrates this, the attribute count is fetched
and returned to the caller through the variable named in `$1`.
Afterwards the attribute is incremented:

~~~ bash
foo.countInc() {
	local count
	# Get counter value.
	$this.getCount count
	$caller.setvar "$1" "$count"
	# Increase counter value copy.
	count=$((count + 1))
	# Store the counter value.
	$this.setCount "$count"
}
~~~

This is how a call could look like:

~~~ bash
local count
$obj.countInc count
echo "The current count is $count."
~~~

Note that both the method and the caller use the local variable count, yet by
using `$caller.setvar` the method is still able to overwrite count in the
caller context.

If a method uses no local variables (which is only sensible in very rare
cases), the regular shell builtin setvar can be used to overwrite variables
in the caller context to reduce overhead.

#### 2.1.3. Temporary Objects

The shell offers `local` to create variables that *disappear* when
returning from a function. Similarly bsda:obj offers the deletion
of objects when returning to the caller via the `$caller.delete`
method.

This way it is safe to use temporary objects and return from anywhere
within the method, without bothering with a single point of exit
that takes care of deleting everything.

The following complete example defines the classes `Foo` and `Bar`.
`Bar` uses a temporary of Foo:

~~~ bash
. ./bsda_obj.sh

bsda:obj:createClass Foo \
	i:private:init \
	c:private:clean \
	x:public:use
Foo.init() { echo "Constructing Foo instance"; }
Foo.clean() { echo "Deleting Foo instance"; }
Foo.use() { echo "Using Foo instance"; }

bsda:obj:createClass Bar \
	i:private:init
Bar.init() {
	local foo
	Foo foo
	$caller.delete $foo
	$foo.use
}

Bar bar
echo Exiting
~~~

Note that `foo` can still be used after making it temporary by calling
`$caller.delete`. Hence the script produces the following output:

~~~
Constructing Foo instance
Using Foo instance
Deleting Foo instance
Exiting
~~~

### 2.2. Special Methods

There are two special kinds of methods available, init and cleanup methods.
These methods are special, because they are called implicitly, the first
when an object is created, the second when it is deleted.

The init method is called by the constructor with all arguments apart
from the first one, which is the variable the constructor stores the object
reference in. It can also be called directly.

The purpose of an init method is to initialise attributes during class
creation. If the init method fails (returns a value > 0) the constructor
immediately destroys the object.

The cleanup method is called implicitly by the `delete()` method.

The `delete()` method does not proceed if the cleanup method fails.

The existence of a cleanup method prevents the creation of the  `copy()`
and `serialise()` methods.



## 3. CONSTRUCTOR

This section documents the use of a constructor created by the
`bsda:obj:createClass()` function below.

The name of the class acts as the name of the constructor. The first
parameter is the name of a variable to store the object reference in.
An object reference is a unique id that allows the accessing of all methods
belonging to an object.

The object id is well suited for `grep -F`, which is nice to have when
implementing lists.

The following example shows how to create an object of the type `foo:bar`,
by calling the `foo:bar` constructor:

~~~ bash
foo:bar foobar
~~~

The following example shows how to use a method belonging to the object:

~~~ bash
$foobar.copy foobarCopy
~~~

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The variable to store the reference to the new object in
|  @       | The remaining arguments are forwarded to the init method

Return values:

| Value    | Description
|----------|------------------------------------------------------------
| 0        | Object was successfully constructed
| *        | Object construction failed, most likely in the init method



## 5. DESTRUCTOR

This section documents the use of a destructor created by the
`bsda:obj:createClass()` function below.

The destructor calls a cleanup method with all parameters, if
one was specified. Afterwards it simply removes all method wrappers and
attributes from memory.

* **NOTE**
  The destruction of attributes and method wrappers is avoided when
  the cleanup method fails.

The following example illustrates the use of the destructor on an object
that is referenced by the variable `foobar`.

~~~ bash
$foobar.delete
~~~

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
|  @       | The arguments are forwarded to the cleanup method

Return values:

| Value    | Description
|----------|------------------------------------------------------------
| 0        | If there is no cleanup method
| *        | The return value depends on the cleanup method

Certain data structures may need to dispose of entire lists of objects,
especially within their destructor. This can be done by iterating through
the list or delegating that task to the `bsda:obj:delete[]()` function:

~~~ bash
bsda:obj:delete[] $($this.getChildren)
~~~

Using the shell input field separator logic, this can be used for different
list formats. E.g. a list in the following format:

~~~ bash
<obj0>,<obj1>,<obj2>,
~~~

The objects in this list can be deleted by calling:

~~~ bash
local IFS
IFS=','
bsda:obj:delete[] $($this.getCSChildren)
~~~



## 5. COPY

This section documents the use of a copy method created by the
`bsda:obj:createClass()` function below.

The copy method creates a new object of the same type and copies all
attributes over to the new object.

The following exampe depicts the copying of an object referenced by the
variable `foobar`. The new object will be referenced by the variable
`foobarCopy`.

~~~ bash
$foobar.copy foobarCopy
~~~



## 6. GET

This section documents the use of a getter method created by the
`bsda:obj:createClass()` function below.

A getter method either outputs an attribute value to stdout or stores it
in a variable, named by the first parameter.

The following example shows how to get the attribute `value` from the object
referenced by `foobar` and store it in the variable `value`.

~~~ bash
$foobar.getValue value
~~~

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The variable to store the value in



## 7. SET

This section documents the use of a setter method created by the
`bsda:obj:createClass()` function below.

A setter method stores a value in an attribute.

This example shows how to store the value 5 in the attribute `value` of
the object referenced by `foobar`.

~~~ bash
$foobar.setValue 5
~~~

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
|  1       | The value to write to an attribute.



## 8. TYPE CHECKS

This framework supplies basic type checking facilities.

### 8.1. Object Type Checks

This section documents the use of the static type checking method created
by the `bsda:obj:createClass()` function.

The type checking method `isInstance()` takes an argument string and checks
whether it is a reference to an object of this class.

This example shows how to check whether the object `foobar` is an instance
of the class `foo:bar`.

~~~ bash
if foo:bar.isInstance $foobar; then
	…
else
	…
fi
~~~

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
|  1       | Any string that might be a reference.

### 8.2. Primitive Type Checks

The following primitive type checking functions are available and documented
in the code:

- `bsda:obj:isObject()`
- `bsda:obj:isInt()`
- `bsda:obj:isUInt()`
- `bsda:obj:isFloat()`
- `bsda:obj:isSimpleFloat()`



## 9. SERIALISE

This documents the process of serialisation and deserialisation.
Serialization is the process of turning data structures into string
representations. Serialised objects can be stored in a file and reloaded
at a later time. They can be passed on to other processess, through a file
or a pipe. They can even be transmitted over a network through nc(1).

* **NOTE** Static attributes are not subject to serialisation.

### 9.1. Serialising

The following example serialises the object `$foobar` and stores the string
the variable serialised.

~~~ bash
$foobar.serialise serialised
~~~

The next example saves the object `$configuration` in a file.

~~~ bash
$configuration.serialise > ~/.myconfig
~~~

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The variable to store the serialised string in

### 9.2. Deserialising

This example loads the object `$configuration` from a file and restores it.

~~~ bash
# Deserialise the data and get the object reference.
bsda:obj:deserialise configuration < ~/.myconfig
~~~

After the last line the `$configuration` object can be used exactly like
in the previous session.

Serialised data is executable shell code that can be fed to eval, however
the `bsda:obj:deserialise()` function should always be used to ensure that
deserialisation happens in a controlled environment.

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The variable to store the deserialised object reference in
|  2       | The string to be deserialised, can be provided on stdin

### 9.3. Filtering

Sometimes a lot of serialised data has to be deserialised that contains
stale objects. For such cases the serialised data can be filtered to contain
only the last occurance of each object.

~~~ bash
bsda:obj:serialisedUniq serialised "$serialised"
~~~

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The variable to store the resulting string in
|  2       | The serialised data, can be provided on stdin

### 9.4. Dumping

The `dump()` method provides a human readable serialising format.
Its purpose is debugging data structures instead of providing a way
to store and retrieve objects.

The `dump()` method is provided by any object:

~~~ bash
. bsda_opts.sh

bsda:opts:Options options \
HELP -h --help "Display usage and exit" \
FOO  -f --foo  "The foo in foobar" \
BAR  -b --bar  "The bar in foobar"

$options.dump
~~~

The above script generates output like the following:

~~~
bsda:opts:Options@BSDA_OBJ_bsda_obj_bsda_opts_Options_b1b60cca_fa75_11e6_8944_0090f5f2f347_0_ {
  Next=bsda:opts:Options@BSDA_OBJ_bsda_obj_bsda_opts_Options_b1b60cca_fa75_11e6_8944_0090f5f2f347_1_ {
    Next=bsda:opts:Options@BSDA_OBJ_bsda_obj_bsda_opts_Options_b1b60cca_fa75_11e6_8944_0090f5f2f347_2_ {
      Next=
      ident='BAR'
      short='-b'
      long='--bar'
      desc='The bar in foobar'
    }
    ident='FOO'
    short='-f'
    long='--foo'
    desc='The foo in foobar'
  }
  ident='HELP'
  short='-h'
  long='--help'
  desc='Display usage and exit'
}
~~~



## 10. REFLECTION & REFACTORING

The bsda:obj framework offers full reflection. Refactoring is not supported,
but possible to a limited degree.

Internally the reflection support is required for realising aggregation.

### 10.1. Attributes

Each class offers the static method `getAttributes()`:

~~~ bash
<classname>.getAttributes attributes
~~~

The variable attributes then contains a list of all attributes an instance
of this class has. The list is newline separated.

Every attribute of an instance can directly be accessed, bypassing the scope
checks (object is an instance of the class the list attributes was
determined from):

~~~ bash
for attribute in $attributes; do
	echo -n "$attribute: "
	# Print the attribute value
	getvar $object$attribute
done
~~~

### 10.2. Methods

Each class also offers the static method `getMethods()`:

~~~
<classname>.getMethods methods
~~~

The methods variable in the example then contains a list of methods in the
format:

~~~
("private" | "public") + ":" + <methodname>
~~~

The methods are newline separated.

Every method can be overwritten, by redefining it. The access scope checks
remain the same.



## 11. FORKING PROCESSES

One of the intended uses of serialising is that a process forks and both
processes are able to pass new or updated objects to each others and thus
keep each other up to date.

When a process is forked, both processes retain the same state, which can
lead to multiple processes generating objects with identical IDs.

Additional garbage collection needs to be reinitialised in the forked
process to ensure all acquired resources are freed when the process
terminates.

### 11.1. Creating Child Processes

The function `bsda:obj:fork()` can be used to circumvent this problem by
regenerating `bsda_obj_uid`, resetting `bsda_obj_freeOnExit` and setting
up traps for `SIGHUP`, `SIGINT`, `SIGTERM` and the `EXIT` handler.

The following example illustrates its use.

~~~ bash
(
	bsda:obj:fork
	# Do something …
) &
~~~

The `bsda:obj:fork()` call must not be omitted or non-memory resources may
be freed while still in use.

### 11.2. Detaching from the Execution Context

Detaching into the background by forking off a process and exiting would
invoke garbage collection and cause the process to hang until all child
processes are dead.

To circumvent this the `bsda:obj:detach()` function can be used. It calls
a given command in a forked process. The responsibility to free resources
upon termination is passed on to the forked process, while the original
process terminates, omitting garbage collection:

~~~ bash
bsda:obj:detach $this.daemon
~~~



## 12. GARBAGE COLLECTION

In order to prevent resource leaks `bsda:obj` performs some lazy garbage
collection.

A list of objects with a cleanup method is maintained in
`bsda_obj_freeOnExit`. These objects are explicitly deleted if the shell
exits due to the `exit` command or the signals `SIGHUP`, `SIGINT`
or `SIGTERM`.

This gives objects the opportunity to free non-memory resources. Note that
these actions are only performed within the process that originally created
an object. This ensures that such resources are not freed multiple times.



## 13. FILE DESCRIPTORS

The _FreeBSD_ `sh` only allows file descriptor numbers up to 9. The numbers
1 and 2 are used for `stdout` and `stderr`, that means only 7 descriptors are
available overall.

File descriptors are useful for interacting with files and named pipes
without closing the pipe between reads/writes.

In order to manage them effectively the `bsda:obj:getDesc()` function provides
a descriptor number and `bsda:obj:releaseDesc()` allows returning one into
the pool of available numbers.

~~~ bash
local fd
bsda:obj:getDesc fd || return 1
# Open file descriptor
eval "exec $fd> \"\$outfile\""
[ … ]
# Close file descriptor
eval "exec $fd>&-"
bsda:obj:releaseDesc $fd
~~~

Arguments to `bsda:obj:getDesc()`:

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The variable to store the file descriptor number in

Return values of `bsda:obj:getDesc()`:

| Value    | Description
|----------|------------------------------------------------------------
| 0        | The function succeeded in returning a file descriptor
| 1        | No more file descriptors were available

Arguments to `bsda:obj:releaseDesc()`:

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The file descriptor to release



## 14. COMPATIBILITY

This framework was written for the bourne shell clone, provided with the
_FreeBSD_ operating system (a descendant of the _Almquist shell_). To open it
up to a wider audience it was made compatible to the _Bourne-again shell_
(bash) version 4, though it is likely to work with earlier releases, too.

The performance of `bash` however is very bad (more than thrice the runtime
of _FreeBSD's ASH_ derivate for the tested cases). Unfortunately the only
popular _ASH_ derivate in the _GNU_ world, `dash`, is not compatible.
Compatibility could be achieved, but the syntactical impact was deemed too
painful.

Compatibilty hacks can be found at the very end of `bsda_obj.sh`. This chapter
describes some of the differences between FreeBSD `sh` and `bash` that one
might have to keep in mind when implementing classes with this framework.

### 14.1. POSIX

The relatively strict _POSIX_ conformance of `dash` is the reason that this
framework is not compatible to it. The specific reason why this framework
does not work with `dash` is the use of colon `:` and period `.` characters
in function and method names. [POSIX][] only requires a shell to support
function names consisting of the character group `[_[:alnum:]]`.

However it also states that a shell may allow other characters. The
resulting paradox is that supporting colons and periods in function names
is _POSIX_ conformant, whereas using them isn't.

One might argue that _POSIX_ conformance should be the top priority to a
general purpose framework such as this one. An example for an object
oriented shell framework doing just that is [Shoop][], which originates from
the _Debian_ project.

_Shoop_ is a good example why _POSIX_ support is only of secondary concern for
the `bsda:obj` development. Using _Shoop_ neither feels like writing shell code
nor like using one of the popular OO languages.

Preserving the shell scripting _feeling_ and introducing similarities to
popular OO languages were the main syntactical goals for `bsda:obj`.
These goals were not compatible to the goal of full _POSIX_ conformance and
took precendence.

A good example why _POSIX_ conformance is overrated is the `local` function.
_POSIX_ neither requires nor defines it. Arguably large shell scripts
would become very tedious, considering that all variables would then
be global and their names would have to be chosen with extraordinary care,
not to mention the problems for recursion.

Even `dash` with its strict _POSIX_ conformance provides the `local` builtin.
Considering that, one might argue it should add colon and period support for
function names as well, because the `.` and `:` builtin functions imply that
`.` and `:` are valid function names.

  [POSIX]: http://www.opengroup.org/onlinepubs/009695399/utilities/xcu_chap02.html#tag_02_09_05
  [Shoop]: http://shoop.cvs.sourceforge.net/viewvc/shoop/shoop/docs/README?view=markup

### 14.2. bash - local

The `local` command of bash destroys the original variable values when
declaring a variable local. Most notably that broke scope checks.
A simple workaround was to move the local decleration behind the scope
checks in the code.

### 14.3. bash - setvar

The `bash` does not have a setvar command. A hack was introduced to circumvent
this.

### 14.4. bash - Command Substitution Variable Scope

Variable changes inside command substition are lost outside the scope of the
substition, when using `bash`. The _FreeBSD_ `sh` performs command
substitution in the same variable scope, which sometimes can be used for
elegant solutions, where bash compatibility requires the use of additional
temporary variables.

The following code will output `ab` when executed by _FreeBSD's_ `sh` and `aa`
when executed with `bash`:

~~~ bash
test=a
echo $test$(test=b)$test
~~~

### 14.5. bash - alias

The `alias` command in `bash`, used for inheritance in the framework, only
works in interactive mode. Hence all uses of `alias` had to be substituted with
slightly slower function wrappers.

