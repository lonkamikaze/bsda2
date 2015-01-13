	    ______  ______  ___     _____      _____   ______ ______
	   /  _  / /   __/ /   \   /  _  / __ /  _  \ /  _  //___  /
	  /  ___/  \  \   /  /  \ /     / /_//  //  //  ___/    / /
	 /  __  /__/   \ /  /   //  //  /__ /  //  //  __  /   / /
	/______//______//______//__//__//_/ \_____//______/   / /
	                                  ___________________/ /
	WORSE THAN PERL™ SINCE 2009      /____________________/

BSDA:OBJ - Real World OO for Shell-Scripting
============================================

This framework was originally developed for the now obsolete pkg_upgrade
from the first gen BSD Adminstration Scripts. Back in the day the shell
based portmaster had pretty much replaced the perl based portupgrade as
the goto ports management tool. And I was of the opinion that anything
but a shell script would not gain any user acceptance.

So back in 2009 at the [GPN8 hacker conference][GPN8], I started working on
this.  I presented it at the EuroBSDCon 2010 with [a talk and a
paper][2010EuroBSDCon]. 

Then the whole endeavour came to rest as I was busy [building race
cars][HSK], which mostly resulted in [C code][HSKSF].

Finally, during the [31C3][] I rewrote pkg_libchk on a whim and revived
bsda:obj along with it.

[GPN8]: https://entropia.de/GPN8
[2010EuroBSDCon]: http://2010.eurobsdcon.org/presentations-schedule/paper-detail-view/?tx_ptconfmgm_controller_detail_paper[uid]=17&tx_ptconfmgm_controller_detail_paper[pid]=299
[HSK]: http://highspeed-karlsruhe.de/
[HSKSF]: http://hsk.sf.net/
[31C3]: https://events.ccc.de/congress/2014/


TABLE OF CONTENTS
-----------------

1. DEFINING CLASSES
   1. Basic Class Creation
   2. Inheritance
   3. Access Scope
   4. Interfaces
2. IMPLEMENTING METHODS
   1. Regular Methods
   2. Special Methods
3. CONSTRUCTOR
4. RESET
5. DESTRUCTOR
6. COPY
7. GET
8. SET
9. TYPE CHECKS
    1. Object Type Checks
    2. Primitive Type Checks
10. SERIALIZE
    1. Serialising
    2. Deserialising
    3. Filtering
11. REFLECTION & REFACTORING
    1. Attributes
    2. Methods
    3. Parent Classes and Interfaces
12. FORKING PROCESSES
13. GARBAGE COLLECTION
14. FILE DESCRIPTORS
15. COMPATIBILITY
    1. POSIX
    2. bash - local
    3. bash - setvar
    4. bash - Command Substitution Variable Scope
    5. bash - alias


## 1. DEFINING CLASSES

This section describes the creation of classes.

* NOTE: The details of creating classes are listed in front of the
  bsda:obj:createClass() function.

Creating a class consists of two steps, the first step is to call
the bsda:obj:createClass() function, the second one is to implement the
methods. This section describes the first step.

In order to create classes this framework has to be loaded:

	. ./bsda_obj.sh

### 1.1. Basic Class Creation

Creating a class does not require more than a class name:

	bsda:obj:createClass MyClass

After the previous line the class can be used to create objects,
however useless, and all the reserved methods are available:

	MyClass myObject
	$myObject.delete

It is possible to create classes as simple data structures, that do not
require the programmer to write any methods to function:

	bsda:obj:createClass MyPoint2D \
		w:name \
		w:x \
		w:y

Instances of the MyPoint2D class now offer the getName() and setName(),
getX() and setX(), getY() and setY() methods:

	MyPoint2D point
	$point.setName "upper left corner"
	$point.setX 0
	$point.setY 0

It might be a good idea to add an init method to the class in order to
assign values:

	bsda:obj:createClass MyConstPoint2D \
		i:init \
		r:name \
		r:x \
		r:y
	
	MyConstPoint2D.init() {
		[ ... assign values, maybe even check types ... ]
	}

* NOTE: The init method can have an arbitrary name.

Note that the attributes were now created with "r:", this means they only
have get methods, no set methods. All the values are now assigned during
object creation by the init method:

	MyConstPoint2D corner "upper right corner" 640 0

### 1.2. Inheritance

If a similar class is required there is no reason to start anew, the
previous class can be extended:

	bsda:obj:createClass MyConstPoint3D extends:MyConstPoint2D \
		i:init \
		r:z
	
	MyConstPoint3D.init() {
		# Call the init method of the parent class.
		$class.superInit "$1" "$2" "$3" || return 1
		# Check whether the given coordinate is an integer.
		bsda:obj:isInt "$4" || return 1
		setvar ${this}z "$4"
	}

The init method is explicitely stated in the class declaration just for the
sake of readability, though not a requirement for overloading inherited
methods, this is considered good style.

* NOTE: If the init method does not return 0 the object is instantly
  destroyed and the return value is forwarded to the caller.
  The caller then has a reference to a no longer existing object
  and does not know about it, unless the return value of the
  constructor is checked.

Multiple inheritance is possible, but should be used with great care,
because there are several limits. If several extended classes provide
the same method, the method of the first class has the priority.

The super init and cleanup methods are those of the first class providing
an init or cleanup method.
The remaining init and cleanup methods might continue to exist as regular
methods, if their names do not conflict.

Inherited methods become part of a class. Thus inherited private methods
are readily available to every method of the class, even new methods or
methods inherited from different classes.

It also means that even instances of the originating class do not have
access to private methods. This behaviour contradicts common expectations.
The different paradigm is that access scope in this framework manages
access to the current context instead of access to certain code.

### 1.3. Access Scope

You might want to limit access to certain methods, for this you can
add the scope operators private, protected and public. If no scope
operator is given, public is assumed.

- public: This scope allows access from anywhere
- protected: The protected scope allows classes that are derived from the
  current class, parents of the corrunt class or reside within
  the same namespace access
- private: Only instances of the same class have access

Namespaces are colon (the character ":") seperated. E.g. the class
bsda:pkg:Index has the namespace "bsd:pkg".

The scope operator is added after the identifier type prefix. Only
prefixes that declare methods can have a scope operator.

	bsda:obj:createClass myNs:Person \
		i:private:init \
		w:private:familyName \
		w:private:firstName

* NOTE: The constructor is always public. Declaring a scope for an init method
  only affects direct calls of the method.

Now the getters and setters for both familyName and firstName are private.
It is possible to widen the scope of a method by redeclaring it.

	bsda:obj:createClass myNs:Person \
		i:private:init \
		w:private:familyName \
		x:public:getFamilyName \
		w:private:firstName \
		x:public:getFirstName

* NOTE: When methods are inherited the widest declared scope always wins, no
  matter from which class it originates.

### 1.4. Interfaces

Implementations of generic solutions normally require the classes using them
to conform to a certain interface (e.g. in a listener and notify pattern).

Technically this can be realized with inheritance, but this is often a dirty
solution, especially when conformance to several interfaces is required.

To circumvent the consistency problems imposed by multiple inheritance the
bsda:obj:createInterface() method allows the creation of interfaces:

	bsda:obj:createInterface Listener \
		x:notify

* NOTE: Methods defined by an interface are always public, so there is not
  scope operator.

* NOTE: Interfaces cannot be used to define attributes.

Every class conforming to the interface has to implement the methods defined
by the interface:

	bsda:obj:createClass Display implements:Listener \
		[ ... additional method and attribute definitions ... ]

	Display.notify() {
		[ ... ]
	}

Interfaces can also extend other interfaces.

To check whether an object is derived from a class conforming to an
interface the static isInstance method can be use:

	if ! Listener.isInstance $object; then
		[ ... ]
	fi



## 2. IMPLEMENTING METHODS

All that remains to be done to get a functional class after defining it,
is to implement the required methods.
Methods are really just functions that the constructor
creates a wrapper for that forwards the object reference to them.

### 2.1. Regular Methods

The following special variables are available:
	this	A reference to the current object
	class	The name of the class this object is an instance of
	caller	Provides access to methods to manipulate the caller context,
		which is the recommended way of returning data to the caller

The following methods are offered by the caller:
	setvar	Sets a variable in the caller context.
	getObject
		Returns a reference to the calling object.
	getClass
		Returns the name of the calling class.

The following variable names may not be used in a method:
	_return
	_var
	_setvars

A method must always be named "<class>.<method>". So a valid implementation
for a method named "bar" and a class named "foo" would look like this:

	foo.bar() {
	}

The object reference is always available in the variable "this", which
performs the same function as "self" in python or "this" in Java.

Attributes are resolved as "<objectId><attribute>", the following example
shows how to read an attribute, manipulate it and write the new value.
Directly operating on attributes is not possible.

	foo.bar() {
		local count
		# Get counter value.
		bsda:obj:getVar count ${this}count
		# Increase counter value copy.
		count=$(($count + 1))
		# Store the counter value.
		setvar ${this}count $count
	}

The following example does the same with getters and setters. Getters and
setters are documented in chapter 7 and 8.

	foo.bar() {
		local count
		# Get counter value.
		$this.getCount count
		# Increase counter value copy.
		count=$(($count + 1))
		# Store the counter value.
		$this.setCount $count
	}

To return data into the calling context $caller.setvar is used. It
provides the possibility to overwrite variables in the caller context
even when there is a local variable using the same name.
Note that it has to be assumed that the names of variables used within
a method are unknown to the caller, so this can always be the case.

The name of the variable to store something in the caller context is
normally given by the caller itself as a parameter to the method call.

The following method illustrates this, the attribute count is fetched
and returned to the caller through the variable named in $1.
Afterwards the attribute is incremented:

	foo.countInc() {
		local count
		# Get counter value.
		$this.getCount count
		$caller.setvar $1 $count
		# Increase counter value copy.
		count=$(($count + 1))
		# Store the counter value.
		$this.setCount $count
	}

This is how a call could look like:

	local count
	$obj.countInc count
	echo "The current count is $count."

Note that both the method and the caller use the local variable count, yet by
using $caller.setvar the method is still able to overwrite count in the
caller context.

If a method uses no local variables (which is only sensible in very rare
cases), the regular shell builtin setvar can be used to overwrite variables
in the caller context to reduce overhead.

### 2.2. Special Methods

There are two special kinds of methods available, init and cleanup methods.
These methods are special, because they are called implicitely, the first
when an object is created, the second when it is reset or deleted.

The init method is special because the $caller.setvar() method is not
available. It is called by the constructor with all values apart from the
first one, which is the variable the constructor stores the object
reference in. It can also be called directly (e.g. after a call to the
reset() method).

The purpose of an init method is to initialize attributes during class
creation. If the current class is derived from another class it might
be a good idea to call the init method of the parent class. This is
done by calling $class.superInit().

If the init method fails (returns a value > 0) the constructor immediately
destroys the object.

The cleanup method is called implicitely by the delete() and reset()
methods. Unlike the init method it has all the posibilities of an
ordinary method.

Both the delete() and reset() methods do not proceed if the cleanup
method fails.



## 3. CONSTRUCTOR

This block documents the use of a constructor created by the
bsda:obj:createClass() function below.

The name of the class acts as the name of the constructor. The first
parameter is the name of a variable to store the object reference in.
An object reference is a unique id that allows the accessing of all methods
belonging to an object.

The object id is well suited for "grep -F", which is nice to have when
implementing lists.

The following example shows how to create an object of the type "foo:bar",
by calling the "foo:bar" constructor:

	foo:bar foobar

The following example shows how to use a method belonging to the object:

	$foobar.copy foobarCopy

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



## 4. RESET

This block documents the use of a resetter created by the
bsda:obj:createClass() function below.

The resetter first calls the cleanup method with all parameters, if one
has been defined. Afterwards it simply removes all attributes from memory.

* NOTE: The destruction of attributes is avoided when the cleanup method fails.

The resetter does not call the init method afterwards, because it would
not be possible to provide different parameters to the init and cleanup
methods in that case.

The following example shows how to reset an object referenced by "foobar".

	$foobar.reset

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
|  @       | The arguments are forwarded to the cleanup method

Return values:

| Value    | Description
|----------|------------------------------------------------------------
| 0        | If there is no cleanup method
| *        | The return value depends on the cleanup method



## 5. DESTRUCTOR

This block documents the use of a destructor created by the
bsda:obj:createClass() function below.

The destructor calls a cleanup method with all parameters, if
one was specified. Afterwards it simply removes all method wrappers and
attributes from memory.

* NOTE: The destruction of attributes and method wrappers is avoided when
  the cleanup method fails.

The following example illustrates the use of the destructor on an object
that is referenced by the variable "foobar".

	$foobar.delete

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
|  @       | The arguments are forwarded to the cleanup method

Return values:

| Value    | Description
|----------|------------------------------------------------------------
| 0        | If there is no cleanup method
| *        | The return value depends on the cleanup method



## 6. COPY

This block documents the use of a copy method created by the
bsda:obj:createClass() function below.

The copy method creates a new object of the same type and copies all
attributes over to the new object.

The following exampe depicts the copying of an object referenced by the
variable "foobar". The new object will be referenced by the variable
"foobarCopy".

	$foobar.copy foobarCopy



## 7. GET

This block documents the use of a getter method created by the
bsda:obj:createClass() function below.

A getter method either outputs an attribute value to stdout or stores it
in a variable, named by the first parameter.

The following example shows how to get the attribute "value" from the object
referenced by "foobar" and store it in the variable "value".

	$foobar.getValue value

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The variable to store the value in



## 8. SET

This block documents the use of a setter method created by the
bsda:obj:createClass() function below.

A setter method stores a value in an attribute.

This example shows how to store the value 5 in the attribute "value" of
the object referenced by "foobar".

	$foobar.setValue 5

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
|  1       | The value to write to an attribute.



## 9. TYPE CHECKS

This framework supplies basic type checking facilities.

### 9.1. Object Type Checks

This block documents the use of the static type checking method created
by the bsda:obj:createClass() and bsda:obj:createInterface() function below.

The type checking method isInstance() takes an argument string and checks
whether it is a reference to an object of this class.

This example shows how to check whether the object "foobar" is an instance
of the class "foo:bar".

	if foo:bar.isInstance $foobar; then
		...
	else
		...
	fi

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
|  1       | Any string that might be a reference.

### 9.2. Primitive Type Checks

The following primitive type checking functions are available and documented
in the code:

- bsda:obj:isObject()
- bsda:obj:isInt()
- bsda:obj:isUInt()
- bsda:obj:isFloat()
- bsda:obj:isSimpleFloat()



## 10. SERIALIZE

This documents the process of serialisation and deserialisation.
Serialization is the process of turning data structures into string
representations. Serialized objects can be stored in a file and reloaded
at a later time. They can be passed on to other processess, through a file
or a pipe. They can even be transmitted over a network through nc(1).

* NOTE: Static attributes are not subject to serialisation.

### 10.1. Serialising

The following example serialises the object $foobar and stores the string
the variable serialised.

	$foobar.serialise serialised

The next example saves the object $configuration in a file.

	$configuration.serialise > ~/.myconfig

If $configuration references other objects it will fail to access them
if deserialised in a new context.
This is what the serialiseDeep() method is good for. It serialises entire
data structures recursively and is the right choice in many use cases.
It is used in exactly the same way as the serialise method.

	$configuration.serialiseDeep > ~/.myconfig

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The variable to store the serialised string in

### 10.2. Deserialising

This example loads the object $configuration from a file and restores it.

	# Deserialise the data and get the object reference.
	bsda:obj:deserialise configuration < ~/.myconfig

After the last line the $configuration object can be used exactly like
in the previous session.

Serialized data is executable shell code that can be fed to eval, however
the bsda:obj:deserialise() function should always be used to ensure that
deserialisation happens in a controlled environment.

Arguments:

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The variable to store the deserialised object reference in
|  2       | The string to be deserialised, can be provided on stdin

### 10.3. Filtering

Sometimes a lot of serialised data has to be deserialised that contains
stale objects. For such cases the serialised data can be filtered to contain
only the last occurance of each object.

	bsda:obj:serialisedUniq serialised "$serialised"

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The variable to store the resulting string in
|  2       | The serialised data, can be provided on stdin



## 11. REFLECTION & REFACTORING

The bsda:obj framework offers full reflection. Refactoring is not supported,
but possible to a limited degree.

Internally the reflection support is required for realizing inheritance.
A new class tells all its parents "I'm one of yours" and takes all the
methods and attributes for itself.

### 11.1. Attributes

Each class offers the static method getAttributes():

	<classname>.getAttributes attributes

The variable attributes then contains a list of all attributes an instance
of this class has. The list is newline separated.

Every attribute of an instance can directly be accessed, bypassing the scope
checks (object is an instance of the class the list attributes was
determined from):

	for attribute in $attributes; do
		echo $attribute:
		# Print the attribute value
		bsda:obj:getVar $object$attribute
	done

### 11.2. Methods

Each class also offers the static method getMethods():

	<classname>.getMethods methods

The methods variable in the example then contains a list of methods in the
format:

	("private" | "protected" | "public") + ":" + <methodname>

The methods are newline separated.

Every method can be overwritten, by redefining it. The access scope checks
remain the same. To access a private or protected method of an unrelated
object, the class and identity of the caller can be faked by rewriting the
class and this special variables:

	# Preserve context
	local tmpThis tmpClass
	tmpThis="$this"
	tmpClass="$class"

	# Call forbidden method
	this=$object
	class=<objectclass>
	$object.<methodname>

	# Restore context
	this=$tmpThis
	class=$tmpClass

### 11.3. Parent Classes and Interfaces

Each class knows its parents and interfaces and reveals them through the
static getParents() and getInterfaces() methods:

	<classname>.getInterfaces interfaces
	<classname>.getParents parents

The variables interfaces and parents contain newline separated lists of
interface and class names after the preceding commands.

Though all classes know their parents, they do not know their children.
Instead there is a recognition pattern for object IDs belonging to the
class, which is used by the static isInstance() method for each class.

Every inheriting/implementing class adds a pattern for itself to the
recognition pattern of each class and interface it extends and implements.
This pattern can be accessed through the class prefix:

	<classname>.getPrefix prefix
	bsda:obj:getVar patterns ${prefix}instancePatterns

The class prefix can also be used to access the code for the access scope
checks. This can be abused to deactivate theses checks for a certain class:

	unset ${prefix}public ${prefix}protected ${prefix}private



## 12. FORKING PROCESSES

One of the intended uses of serialising is that a process forks and both
processes are able to pass new or updated objects to each others and thus
keep each other up to date.

When a process is forked, both processes retain the same state, which can
lead to multiple processes generating objects with identical IDs.

Additionall garbage collection needs to be reinitialised in the forked
process to ensure all acquired resources are freed when the process
terminates.

The function bsda:obj:fork() can be used to circumvent this problem by
regenerating bsda_obj_uid, resetting bsda_obj_freeOnExit and setting
up traps for SIGINT, SIGTERM and the EXIT handler.

The following example illustrates its use.

	(
		bsda:obj:fork
		# Do something ...
	) &



## 13. GARBAGE COLLECTION

In order to prevent resource leaks bsda:obj performs some lazy garbage
collection.

A list of objects with a cleanup method is maintained in
bsda_obj_freeOnExit. These objects are explicitly deleted if the shell
exits due to the exit command or the signals SIGINT or SIGTERM.

This gives objects the opportunity to free non-memory resources. Note that
these actions are only performed within the process that originally created
an object. This ensures that such resources are not freed multiple times.



## 14. FILE DESCRIPTORS

The FreeBSD sh only allows file descriptor numbers up to 9. The numbers
1 and 2 are used for stdout and stderr, that means only 7 descriptors are
available overall.

File descriptors are useful for interacting with files and named pipes
without closing the pipe between reads/writes.

In order to manage them effectively the bsda:obj:getDesc() function provides
a descriptor number and bsda:obj:releaseDesc() allows returning one into
the pool of available numbers.

	local fd
	bsda:obj:getDesc fd || return 1
	# Open file descriptor
	eval "exec $fd> \"\$outfile\""
	[ ... ]
	# Close file descriptor
	eval "exec $fd>&-"
	bsda:obj:releaseDesc $fd

Arguments to bsda:obj:getDesc():

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The variable to store the file descriptor number in

Return values of bsda:obj:getDesc():

| Value    | Description
|----------|------------------------------------------------------------
| 0        | The function succeeded in returning a file descriptor
| 1        | No more file descriptors were available

Arguments to bsda:obj:releaseDesc():

| Argument | Description
|----------|------------------------------------------------------------
| &1       | The file descriptor to release



## 15. COMPATIBILITY

This framework was written for the bourne shell clone, provided with the
FreeBSD operating system (a descendant of the Almquist shell). To open it
up to a wider audience it was made compatible to the bourne again shell
(bash) version 4, though it is likely to work with earlier releases, too.

The performance of bash however is very bad (more than thrice the runtime
of FreeBSD's ASH derivate for the tested cases). Unfortunately the only
popular ASH derivate in the GNU world, dash, is not compatible.
Compatibility could be achieved, but the syntactical impact was deemed too
painful.

The serialisation relies on external commands that might not be present
everywhere, namely b64encode(1) and b64decode(1)

Compatibilty hacks can be found at the very end of the file. This chapter
describes some of the differences between FreeBSD sh and bash that one
might have to keep in mind when implementing classes with this framework.

### 15.1. POSIX

The relatively strict POSIX conformance of dash is the reason that this
framework is not compatible to it. The specific reason why this framework
does not work with dash is the use of colon ':' and period '.' characters
in function and method names. [POSIX][] only requires a shell to support
function names consisting of the character group [_[:alnum:]].

However it also states that a shell may allow other characters. The
resulting paradox is that supporting colons and periods in function names
is POSIX conformant, whereas using them isn't.

One might argue that POSIX conformance should be the top priority to a
general purpose framework such as this one. An example for an object
oriented shell framework doing just that is [Shoop][], which originates from
the Debian project.

Shoop is a good example why POSIX support is only of secondary concern for
the bsda:obj development. Using Shoop neither feels like writing shell code
nor like using one of the popular OO languages.

Preserving the shell scripting "feeling" and introducing similarities to
popular OO languages were the main syntactical goals for bsda:obj.
These goals were not compatible to the goal of full POSIX conformance and
took precendence.

A good example why POSIX conformance is overrated is the local function.
POSIX neither requires nor defines it. Arguably large shell scripts
would become very tedious, considering that all variables would then
be global and their names would have to be chosen with extraordinary care.

Even dash with its strict POSIX conformance knows the local builtin.
Considering that, one might argue it should add colon and period support for
function names as well, because the . and : builtin functions imply that
. and : are valid function names.

[POSIX]: http://www.opengroup.org/onlinepubs/009695399/utilities/xcu_chap02.html#tag_02_09_05
[Shoop]: http://shoop.cvs.sourceforge.net/viewvc/shoop/shoop/docs/README?view=markup

### 15.2. bash - local

The local command of bash destroys the original variable values when
declaring a variable local. Most notably that broke scope checks.
A simple workaround was to move the local decleration behind the scope
checks in the code.

### 15.3. bash - setvar

The bash does not have a setvar command. A hack was introduced to circumvent
this.

### 15.4. bash - Command Substitution Variable Scope

Variable changes inside command substition are lost outside the scope of the
substition, when using bash. The FreeBSD sh performs command substitution in
the same variable scope, which sometimes can be used for elegant solutions,
where bash compatibility requires the use of additional temporary variables.

The following code will output "ab" when executed by FreeBSD-sh and "aa"
when executed with bash:

	test=a
	echo $test$(test=b)$test

### 15.5. bash - alias

The alias command in bash, used for inheritance in the framework, only works
in interactive mode. Hence all uses of alias had to be substituted with
slightly slower function wrappers.

