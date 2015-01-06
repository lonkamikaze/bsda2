#
# Copyright (c) 2009, 2010, 2014, 2015
# Dominic Fandrey <kamikaze@bsdforen.de>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# Include once.
test -n "$bsda_obj" && return 0
set -f
readonly bsda_obj=1

#
# This file contains helper functions for creating object oriented
# shell scripts.
#
# The most significant function is bsda:obj:createClass(), which basically
# creates a class, including getters, setters, a constructor, a destructor,
# a reset and a copy function. It also creates serialisation methods.
#

#
# TABLE OF CONTENTS
#
# 1) DEFINING CLASSES
# 1.1) Basic Class Creation
# 1.2) Inheritance
# 1.3) Access Scope
# 1.4) Interfaces
# 2) IMPLEMENTING METHODS
# 2.1) Regular Methods
# 2.2) Special Methods
# 3) CONSTRUCTOR
# 4) RESET
# 5) DESTRUCTOR
# 6) COPY
# 7) GET
# 8) SET
# 9) TYPE CHECKS
# 9.1) Object Type Checks
# 9.2) Primitive Type Checks
# 10) SERIALIZE
# 10.1) Serialising
# 10.2) Deserialising
# 10.3) Filtering
# 11) FORKING PROCESSES
# 12) GARBAGE COLLECTION
# 13) REFLECTION & REFACTORING
# 13.1) Attributes
# 13.2) Methods
# 13.3) Parent Classes and Interfaces
# 14) COMPATIBILITY
# 14.1) POSIX
# 14.2) bash - local
# 14.3) bash - setvar
# 14.4) bash - Command Substitution Variable Scope
# 14.5) bash - alias
# bsda:obj:createClass()
# bsda:obj:createInterface()
# bsda:obj:getVar()
# bsda:obj:getSerializedId()
# bsda:obj:deserialise()
# bsda:obj:isObject()
# bsda:obj:isInt()
# bsda:obj:isUInt()
# bsda:obj:isFloat()
# bsda:obj:isSimpleFloat()
# bsda:obj:createMethods()
# bsda:obj:deleteMethods()
# bsda:obj:deleteAttributes()
# bsda:obj:callerSetup()
# bsda:obj:callerFinish()
# bsda:obj:callerSetvar()
# bsda:obj:fork()
# bsda:obj:exit()
#

#
# 1) DEFINING CLASSES
#
# This section describes the creation of classes.
#
# NOTE:	The details of creating classes are listed in front of the
#	bsda:obj:createClass() function.
#
# Creating a class consists of two steps, the first step is to call
# the bsda:obj:createClass() function, the second one is to implement the
# methods. This section describes the first step.
#
# In order to create classes this framework has to be loaded:
#
#	. ./bsda_obj.sh
#
# 1.1) Basic Class Creation
#
# Creating a class does not require more than a class name:
#
#	bsda:obj:createClass MyClass
#
# After the previous line the class can be used to create objects,
# however useless, and all the reserved methods are available:
#
#	MyClass myObject
#	$myObject.delete
#
# It is possible to create classes as simple data structures, that do not
# require the programmer to write any methods to function:
#
# 	bsda:obj:createClass MyPoint2D \
#		w:name \
#		w:x \
#		w:y
#
# Instances of the MyPoint2D class now offer the getName() and setName(),
# getX() and setX(), getY() and setY() methods:
#
#	MyPoint2D point
#	$point.setName "upper left corner"
#	$point.setX 0
#	$point.setY 0
#
# It might be a good idea to add an init method to the class in order to
# assign values:
#
#	bsda:obj:createClass MyConstPoint2D \
#		i:init \
#		r:name \
#		r:x \
#		r:y
#	
#	MyConstPoint2D.init() {
#		[ ... assign values, maybe even check types ... ]
#	}
#
# NOTE:	The init method can have an arbitrary name.
#
# Note that the attributes were now created with "r:", this means they only
# have get methods, no set methods. All the values are now assigned during
# object creation by the init method:
#
#	MyConstPoint2D corner "upper right corner" 640 0
#
# 1.2) Inheritance
#
# If a similar class is required there is no reason to start anew, the
# previous class can be extended:
#
#	bsda:obj:createClass MyConstPoint3D extends:MyConstPoint2D \
#		i:init \
#		r:z
#	
#	MyConstPoint3D.init() {
#		# Call the init method of the parent class.
#		$class.superInit "$1" "$2" "$3" || return 1
#		# Check whether the given coordinate is an integer.
#		bsda:obj:isInt "$4" || return 1
#		setvar ${this}z "$4"
#	}
#
# The init method is explicitely stated in the class declaration just for the
# sake of readability, though not a requirement for overloading inherited
# methods, this is considered good style.
#
# NOTE: If the init method does not return 0 the object is instantly
#	destroyed and the return value is forwarded to the caller.
#	The caller then has a reference to a no longer existing object
#	and does not know about it, unless the return value of the
#	constructor is checked.
#
# Multiple inheritance is possible, but should be used with great care,
# because there are several limits. If several extended classes provide
# the same method, the method of the first class has the priority.
#
# The super init and cleanup methods are those of the first class providing
# an init or cleanup method.
# The remaining init and cleanup methods might continue to exist as regular
# methods, if their names do not conflict.
#
# Inherited methods become part of a class. Thus inherited private methods
# are readily available to every method of the class, even new methods or
# methods inherited from different classes.
#
# It also means that even instances of the originating class do not have
# access to private methods. This behaviour contradicts common expectations.
# The different paradigm is that access scope in this framework manages
# access to the current context instead of access to certain code.
#
# 1.3) Access Scope
#
# You might want to limit access to certain methods, for this you can
# add the scope operators private, protected and public. If no scope
# operator is given, public is assumed.
#
# public:
# 	This scope allows access from anywhere.
# protected:
#	The protected scope allows classes that are derived from the
#	current class, parents of the corrunt class or reside within
#	the same namespace access.
# private:
#	Only instances of the same class have access.
#
# Namespaces are colon (the character ":") seperated. E.g. the class
# bsda:pkg:Index has the namespace "bsd:pkg".
#
# The scope operator is added after the identifier type prefix. Only
# prefixes that declare methods can have a scope operator.
#
#	bsda:obj:createClass myNs:Person \
#		i:private:init \
#		w:private:familyName \
#		w:private:firstName
#
# NOTE:	The constructor is always public. Declaring a scope for an init method
#	only affects direct calls of the method.
#
# Now the getters and setters for both familyName and firstName are private.
# It is possible to widen the scope of a method by redeclaring it.
#
#	bsda:obj:createClass myNs:Person \
#		i:private:init \
#		w:private:familyName \
#		x:public:getFamilyName \
#		w:private:firstName \
#		x:public:getFirstName
#
# NOTE:	When methods are inherited the widest declared scope always wins, no
# 	matter from which class it originates.
#
# 1.4) Interfaces
#
# Implementations of generic solutions normally require the classes using them
# to conform to a certain interface (e.g. in a listener and notify pattern).
#
# Technically this can be realized with inheritance, but this is often a dirty
# solution, especially when conformance to several interfaces is required.
#
# To circumvent the consistency problems imposed by multiple inheritance the
# bsda:obj:createInterface() method allows the creation of interfaces:
#
#	bsda:obj:createInterface Listener \
#		x:notify
#
# NOTE:	Methods defined by an interface are always public, so there is not
#	scope operator.
#
# NOTE:	Interfaces cannot be used to define attributes.
#
# Every class conforming to the interface has to implement the methods defined
# by the interface:
#
#	bsda:obj:createClass Display implements:Listener \
#		[ ... additional method and attribute definitions ... ]
#
#	Display.notify() {
#		[ ... ]
#	}
#
# Interfaces can also extend other interfaces.
#
# To check whether an object is derived from a class conforming to an
# interface the static isInstance method can be use:
#
#	if ! Listener.isInstance $object; then
#		[ ... ]
#	fi
#

#
# 2) IMPLEMENTING METHODS
#
# All that remains to be done to get a functional class after defining it,
# is to implement the required methods.
# Methods are really just functions that the constructor
# creates a wrapper for that forwards the object reference to them.
#
# 2.1) Regular Methods
#
# The following special variables are available:
# 	this	A reference to the current object
#	class	The name of the class this object is an instance of
#	caller	Provides access to methods to manipulate the caller context,
#		which is the recommended way of returning data to the caller
#
# The following methods are offered by the caller:
#	setvar	Sets a variable in the caller context.
#	getObject
#		Returns a reference to the calling object.
#	getClass
#		Returns the name of the calling class.
#
# The following variable names may not be used in a method:
#	_return
#	_var
#	_setvars
#
# A method must always be named "<class>.<method>". So a valid implementation
# for a method named "bar" and a class named "foo" would look like this:
#
#	foo.bar() {
#	}
#
# The object reference is always available in the variable "this", which
# performs the same function as "self" in python or "this" in Java.
#
# Attributes are resolved as "<objectId><attribute>", the following example
# shows how to read an attribute, manipulate it and write the new value.
# Directly operating on attributes is not possible.
#
#	foo.bar() {
#		local count
#		# Get counter value.
#		bsda:obj:getVar count ${this}count
#		# Increase counter value copy.
#		count=$(($count + 1))
#		# Store the counter value.
#		setvar ${this}count $count
#	}
#
# The following example does the same with getters and setters. Getters and
# setters are documented in chapter 7 and 8.
#
#	foo.bar() {
#		local count
#		# Get counter value.
#		$this.getCount count
#		# Increase counter value copy.
#		count=$(($count + 1))
#		# Store the counter value.
#		$this.setCount $count
#	}
#
# To return data into the calling context $caller.setvar is used. It
# provides the possibility to overwrite variables in the caller context
# even when there is a local variable using the same name.
# Note that it has to be assumed that the names of variables used within
# a method are unknown to the caller, so this can always be the case.
#
# The name of the variable to store something in the caller context is
# normally given by the caller itself as a parameter to the method call.
#
# The following method illustrates this, the attribute count is fetched
# and returned to the caller through the variable named in $1.
# Afterwards the attribute is incremented:
#
#	foo.countInc() {
#		local count
#		# Get counter value.
#		$this.getCount count
#		$caller.setvar $1 $count
#		# Increase counter value copy.
#		count=$(($count + 1))
#		# Store the counter value.
#		$this.setCount $count
#	}
#
# This is how a call could look like:
#
#	local count
#	$obj.countInc count
#	echo "The current count is $count."
#
# Note that both the method and the caller use the local variable count, yet by
# using $caller.setvar the method is still able to overwrite count in the
# caller context.
#
# If a method uses no local variables (which is only sensible in very rare
# cases), the regular shell builtin setvar can be used to overwrite variables
# in the caller context to reduce overhead.
#
# 2.2) Special Methods
#
# There are two special kinds of methods available, init and cleanup methods.
# These methods are special, because they are called implicitely, the first
# when an object is created, the second when it is reset or deleted.
#
# The init method is special because the $caller.setvar() method is not
# available. It is called by the constructor with all values apart from the
# first one, which is the variable the constructor stores the object
# reference in. It can also be called directly (e.g. after a call to the
# reset() method).
#
# The purpose of an init method is to initialize attributes during class
# creation. If the current class is derived from another class it might
# be a good idea to call the init method of the parent class. This is
# done by calling $class.superInit().
#
# If the init method fails (returns a value > 0) the constructor immediately
# destroys the object.
#
# The cleanup method is called implicitely by the delete() and reset()
# methods. Unlike the init method it has all the posibilities of an
# ordinary method.
#
# Both the delete() and reset() methods do not proceed if the cleanup
# method fails.
#

#
# 3) CONSTRUCTOR
#
# This block documents the use of a constructor created by the
# bsda:obj:createClass() function below.
#
# The name of the class acts as the name of the constructor. The first
# parameter is the name of a variable to store the object reference in.
# An object reference is a unique id that allows the accessing of all methods
# belonging to an object.
#
# The object id is well suited for "grep -F", which is nice to have when
# implementing lists.
#
# The following example shows how to create an object of the type "foo:bar",
# by calling the "foo:bar" constructor:
#
#	foo:bar foobar
#
# The following example shows how to use a method belonging to the object:
#
#	$foobar.copy foobarCopy
#
# @param 1
#	The name of the variable to store the reference to the new object in.
# @param @
#	The remaining parameters are forwarded to an init method,
#	if one was specified.
# @return
#	Returns 0 for success and higher values for failure. If the
#	init method has a fail case, this should be checked, because
#	the object is not created in case of a failure.
#

#
# 4) RESET
#
# This block documents the use of a resetter created by the
# bsda:obj:createClass() function below.
#
# The resetter first calls the cleanup method with all parameters, if one
# has been defined. Afterwards it simply removes all attributes from memory.
#
# NOTE:	The destruction of attributes is avoided when the cleanup method fails.
#
# The resetter does not call the init method afterwards, because it would
# not be possible to provide different parameters to the init and cleanup
# methods in that case.
#
# The following example shows how to reset an object referenced by "foobar".
#
#	$foobar.reset
#
# @param @
#	The parameters are forwareded to a cleanup() method if one was
#	specified.
#

#
# 5) DESTRUCTOR
#
# This block documents the use of a destructor created by the
# bsda:obj:createClass() function below.
#
# The destructor calls a cleanup method with all parameters, if
# one was specified. Afterwards it simply removes all method wrappers and
# attributes from memory.
#
# NOTE:	The destruction of attributes and method wrappers is avoided when
#	the cleanup method fails.
#
# The following example illustrates the use of the destructor on an object
# that is referenced by the variable "foobar".
#
#	$foobar.delete
#
# @param @
#	The parameters are forwareded to a cleanup() method if one was
#	specified.
#

#
# 6) COPY
#
# This block documents the use of a copy method created by the
# bsda:obj:createClass() function below.
#
# The copy method creates a new object of the same type and copies all
# attributes over to the new object.
#
# The following exampe depicts the copying of an object referenced by the
# variable "foobar". The new object will be referenced by the variable
# "foobarCopy".
#
#	$foobar.copy foobarCopy
#

#
# 7) GET
#
# This block documents the use of a getter method created by the
# bsda:obj:createClass() function below.
#
# A getter method either outputs an attribute value to stdout or stores it
# in a variable, named by the first parameter.
#
# The following example shows how to get the attribute "value" from the object
# referenced by "foobar" and store it in the variable "value".
#
#	$foobar.getValue value
#
# @param 1
#	The optional name of the variable to store the attribute value in.
#	If ommitted the value is output to stdout.
#

#
# 8) SET
#
# This block documents the use of a setter method created by the
# bsda:obj:createClass() function below.
#
# A setter method stores a value in an attribute.
#
# This example shows how to store the value 5 in the attribute "value" of
# the object referenced by "foobar".
#
#	$foobar.setValue 5
#
# @param 1
#	The value to write to an attribute.
#

#
# 9) TYPE CHECKS
#
# This framework supplies basic type checking facilities.
#
# 9.1) Object Type Checks
#
# This block documents the use of the static type checking method created
# by the bsda:obj:createClass() and bsda:obj:createInterface() function below.
#
# The type checking method isInstance() takes an argument string and checks
# whether it is a reference to an object of this class.
#
# This example shows how to check whether the object "foobar" is an instance
# of the class "foo:bar".
#
#	if foo:bar.isInstance $foobar; then
#		...
#	else
#		...
#	fi
#
# @param 1
#	Any string that might be a reference.
#
# 9.2) Primitive Type Checks
#
# The following primitive type checking functions are available and documented
# below:
#	bsda:obj:isObject()
#	bsda:obj:isInt()
#	bsda:obj:isUInt()
#	bsda:obj:isFloat()
#	bsda:obj:isSimpleFloat()
#

#
# 10) SERIALIZE
#
# This documents the process of serialisation and deserialisation.
# Serialization is the process of turning data structures into string
# representations. Serialized objects can be stored in a file and reloaded
# at a later time. They can be passed on to other processess, through a file
# or a pipe. They can even be transmitted over a network through nc(1).
#
# NOTE:	Static attributes are not subject to serialisation.
#
# 10.1) Serialising
#
# The following example serialises the object $foobar and stores the string
# the variable serialised.
#
#	$foobar.serialise serialised
#
# The next example saves the object $configuration in a file.
#
#	$configuration.serialise > ~/.myconfig
#
# If $configuration references other objects it will fail to access them
# if deserialised in a new context.
# This is what the serialiseDeep() method is good for. It serialises entire
# data structures recursively and is the right choice in many use cases.
# It is used in exactly the same way as the serialise method.
#
#	$configuration.serialiseDeep > ~/.myconfig
#
# @param 1
#	If given it is used as the variable name to store the serialised string
#	in, otherwise the serialised string is output to stdout.
#
# 10.2) Deserialising
#
# This example loads the object $configuration from a file and restores it.
#
#	# Deserialise the data and get the object reference.
#	bsda:obj:deserialise configuration < ~/.myconfig
#
# After the last line the $configuration object can be used exactly like
# in the previous session.
#
# Serialized data is executable shell code that can be fed to eval, however
# the bsda:obj:deserialise() function should always be used to ensure that
# deserialisation happens in a controlled environment.
#
# @param &1
#	The name of the variable to store the deserialised object reference
#	in. If empty the reference will be output to stdout.
# @param 2
#	If given this is the string to be deserialised, otherwise it will be
#	expected on stdin.
#
# 10.3) Filtering
#
# Sometimes a lot of serialised data has to be deserialised that contains
# stale objects. For such cases the serialised data can be filtered to contain
# only the last occurance of each object.
#
#	bsda:obj:serialisedUniq serialised "$serialised"
#
# @param &1
#	The name of the variable to store the resulting string in.
#	If empty the string is output to stdout.
# @param 2
#	If given this is the serialised data, otherwise it will be
#	expected on stdin.
#

#
# 11) FORKING PROCESSES
#
# One of the intended uses of serialising is that a process forks and both
# processes are able to pass new or updated objects to each others and thus
# keep each other up to date.
#
# When a process is forked, both processes retain the same state, which can
# lead to multiple processes generating objects with identical IDs.
#
# Additionall garbage collection needs to be reinitialised in the forked
# process to ensure all acquired resources are freed when the process
# terminates.
#
# The function bsda:obj:fork() can be used to circumvent this problem by
# regenerating bsda_obj_uid, resetting bsda_obj_freeOnExit and setting
# up traps for SIGINT, SIGTERM and the EXIT handler.
#
# The following example illustrates its use.
#
#	(
#		bsda:obj:fork
#		# Do something ...
#	) &
#

#
# 12) GARBAGE COLLECTION
#
# In order to prevent resource leaks bsda:obj performs some lazy garbage
# collection.
#
# A list of objects with a cleanup() method is maintained in
# bsda_obj_freeOnExit. These objects are explicitly deleted if the shell
# exits due to the exit command or the signals SIGINT or SIGTERM.
#
# This gives objects the opportunity to free non-memory resources. Note that
# these actions are only performed within the process that originally created
# an object. This ensures that such resources are not freed multiple times.
#

#
# 13) REFLECTION & REFACTORING
#
# The bsda:obj framework offers full reflection. Refactoring is not supported,
# but possible to a limited degree.
#
# Internally the reflection support is required for realizing inheritance.
# A new class tells all its parents "I'm one of yours" and takes all the
# methods and attributes for itself.
#
# 13.1) Attributes
#
# Each class offers the static method getAttributes():
#
#	<classname>.getAttributes attributes
#
# The variable attributes then contains a list of all attributes an instance
# of this class has. The list is newline separated.
#
# Every attribute of an instance can directly be accessed, bypassing the scope
# checks (object is an instance of the class the list attributes was
# determined from):
#
#	for attribute in $attributes; do
#		echo $attribute:
#		# Print the attribute value
#		bsda:obj:getVar $object$attribute
#	done
#
# 13.2) Methods
#
# Each class also offers the static method getMethods():
#
#	<classname>.getMethods methods
#
# The methods variable in the example then contains a list of methods in the
# format:
#
#	("private" | "protected" | "public") + ":" + <methodname>
#
# The methods are newline separated.
#
# Every method can be overwritten, by redefining it. The access scope checks
# remain the same. To access a private or protected method of an unrelated
# object, the class and identity of the caller can be faked by rewriting the
# class and this special variables:
#
#	# Preserve context
#	local tmpThis tmpClass
#	tmpThis="$this"
#	tmpClass="$class"
#
#	# Call forbidden method
#	this=$object
#	class=<objectclass>
#	$object.<methodname>
#
#	# Restore context
#	this=$tmpThis
#	class=$tmpClass
#
# 13.3) Parent Classes and Interfaces
#
# Each class knows its parents and interfaces and reveals them through the
# static getParents() and getInterfaces() methods:
#
#	<classname>.getInterfaces interfaces
#	<classname>.getParents parents
#
# The variables interfaces and parents contain newline separated lists of
# interface and class names after the preceding commands.
#
# Though all classes know their parents, they do not know their children.
# Instead there is a recognition pattern for object IDs belonging to the
# class, which is used by the static isInstance() method for each class.
#
# Every inheriting/implementing class adds a pattern for itself to the
# recognition pattern of each class and interface it extends and implements.
# This pattern can be accessed through the class prefix:
#
#	<classname>.getPrefix prefix
#	bsda:obj:getVar patterns ${prefix}instancePatterns
#
# The class prefix can also be used to access the code for the access scope
# checks. This can be abused to deactivate theses checks for a certain class:
#
#	unset ${prefix}public ${prefix}protected ${prefix}private
#

#
# 14) COMPATIBILITY
#
# This framework was written for the bourne shell clone, provided with the
# FreeBSD operating system (a descendant of the Almquist shell). To open it
# up to a wider audience it was made compatible to the bourne again shell
# (bash) version 4, though it is likely to work with earlier releases, too.
#
# The performance of bash however is very bad (more than thrice the runtime
# of FreeBSD's ASH derivate for the tested cases). Unfortunately the only
# popular ASH derivate in the GNU world, dash, is not compatible.
# Compatibility could be achieved, but the syntactical impact was deemed too
# painful.
#
# The serialisation relies on external commands that might not be present
# everywhere, namely b64encode(1) and b64decode(1)
#
# Compatibilty hacks can be found at the very end of the file. This chapter
# describes some of the differences between FreeBSD sh and bash that one
# might have to keep in mind when implementing classes with this framework.
#
# 14.1) POSIX
#
# The relatively strict POSIX conformance of dash is the reason that this
# framework is not compatible to it. The specific reason why this framework
# does not work with dash is the use of colon ':' and period '.' characters
# in function and method names. POSIX only requires a shell to support
# function names consisting of the character group [_[:alnum:]].
# http://www.opengroup.org/onlinepubs/009695399/utilities/xcu_chap02.html#tag_02_09_05
#
# However it also states that a shell may allow other characters. The
# resulting paradox is that supporting colons and periods in function names
# is POSIX conformant, whereas using them isn't.
#
# One might argue that POSIX conformance should be the top priority to a
# general purpose framework such as this one. An example for an object
# oriented shell framework doing just that is Shoop, which originates from
# the Debian project.
# http://shoop.cvs.sourceforge.net/viewvc/shoop/shoop/docs/README?view=markup
#
# Shoop is a good example why POSIX support is only of secondary concern for
# the bsda:obj development. Using Shoop neither feels like writing shell code
# nor like using one of the popular OO languages.
#
# Preserving the shell scripting "feeling" and introducing similarities to
# popular OO languages were the main syntactical goals for bsda:obj.
# These goals were not compatible to the goal of full POSIX conformance and
# took precendence.
#
# A good example why POSIX conformance is overrated is the local function.
# POSIX neither requires nor defines it. Arguably large shell scripts
# would become very tedious, considering that all variables would then
# be global and their names would have to be chosen with extraordinary care.
#
# Even dash with its strict POSIX conformance knows the local builtin.
# Considering that, one might argue it should add colon and period support for
# function names as well, because the . and : builtin functions imply that
# . and : are valid function names.
#
# 14.2) bash - local
#
# The local command of bash destroys the original variable values when
# declaring a variable local. Most notably that broke scope checks.
# A simple workaround was to move the local decleration behind the scope
# checks in the code.
#
# 14.3) bash - setvar
#
# The bash doesn't have a setvar command. A hack was introduced to circumvent
# this.
#
# 14.4) bash - Command Substitution Variable Scope
#
# Variable changes inside command substition are lost outside the scope of the
# substition, when using bash. The FreeBSD sh performs command substitution in
# the same variable scope, which sometimes can be used for elegant solutions,
# where bash compatibility requires the use of additional temporary variables.
#
# The following code will output "ab" when executed by FreeBSD-sh and "aa"
# when executed with bash:
#
#	test=a
#	echo $test$(test=b)$test
#
# 14.5) bash - alias
#
# The alias command in bash, used for inheritance in the framework, only works
# in interactive mode. Hence all uses of alias had to be substituted with
# slightly slower function wrappers.
#

#
# This is a user tunable to turn off scope checks, which can bring
# considerable performance gain, but should only be done with thoroughly
# tested code.
#
# It has to be activated before including the framework. Changing it at
# runtime will have no effect.
#
#BSDA_OBJ_NOSCOPE=

#
# The stack counter that holds the number of methods that currently
# use the return stack.
#
bsda_obj_callStackCount=0

#
# This is a prefix to every object ID and should be the same among all
# compatible frameworks to ensure that deep serialisation works.
#
readonly bsda_obj_frameworkPrefix=BSDA_OBJ_

#
# The interpreting shell command. This can be used when this information is
# needed by other programs like lockf(1).
#
readonly bsda_obj_interpreter="$(/bin/ps -wwo args= -p $$ | /usr/bin/sed -e "s, $(echo "$0${*:+ $*}" | /usr/bin/tr '*?][^$,{}' '.........')\$,,1" -e 's,^\[,,' -e 's,]$,,')"

#
# The UID to use for creating new objects. When forking a session use the
# bsda:obj:fork() function to update this value in the forked process.
#
#bsda_obj_uid

#
# This is used as a buffer during deep serialisation.
#
#bsda_obj_serialised

#
# During deep serialisation this holds a list of objects to prevent circular
# recursion.
#
#bsda_obj_serialiseBlacklist

#
# The copy method sets this temporarily to tell the constructor not to call
# an init method.
#
#bsda_obj_doCopy

#
# A list of objects with a cleanup function, used by the EXIT trap handler
# to allow objects the destruction of acquired resources.
#
#bsda_obj_freeOnExit

#
# Creates a new class, i.e. a constructor, destructor, resetter, getters,
# setters and so forth.
#
# So all that is left to be done are the methods.
#
# The following static methods are reserved:
#	superInit()
#	superClean()
#	deserialise()
#	isInstance()
#	isClass()
#	isInterface()
#	getAttributes()
#	getMethods()
#	getPrefix()
#	getInit()
#	getClean()
#	getParents()
#	getInterfaces()
#
# The following methods are reserved:
#	copy()
#	delete()
#	reset()
#	serialise()
#	serialiseDeep()
#
# The following class prefix bound static attributes are reserved:
#	instancePatterns
#	private
#	protected
#	public
#
# The following session, class and process bound static attributes are
# reserved:
#	nextId
#
# @param 1
#	The first parameter is the name of the class.
# @param @
#	A description of the class to create.
#	
#	All parameters following the class name make up a list of identifiers
#	for attributes and methods. Every identifier has a prefix, the
#	following prefixes are supported:
#
#		-: A plain attribute.
#		r: An attribute with a get method. The identifier
#		   "r:foo" results in a method called "getFoo".
#		w: An attribute with a get and set method. "w:foo" results
#		   in "getFoo" and "setFoo".
#		x: A method, this has to be user implemented as
#		   "<class>.<method>()".
#		i: An init method that is called with the remaining parameters
#		   given to the constructor.
#		c: A cleanup method that is called before the reset or delete
#		   command, with the parameters given to them.
#		extends:
#		   This prefix is followed by the name of another class
#		   this class inherits methods and attributes from.
#		   Classes have to be given in the order of priority.
#
#		   The init and clean methods are inherited from the first
#		   class having them if no own init or clean method is
#		   supplied.
#
#		   The superInit() and superClean() methods also call
#		   the first encountered init and clean methods.
#		implements:
#		   This prefix is followed by the name of an interfaces.
#		   Interfaces define public methods that need to be implemented
#		   by a class to conform to the interface.
#
#	With these parameters a constructor and a destructor will be built.
#	It is important that all used attributes are listed, or the copy,
#	delete and serialisation methods will not work as expected.
#
#	Everything that is not recognized as an identifier is treated as a
#	comment.
#
#	The prefixes r, w, x, i and c can be followed by a scope operator
#	public, protected or private.
#	
#	The constructor can be called in the following way:
#		<class> <refname>
#	The class name acts as the name of the constructor, <refname> is the
#	name of the variable to store the reference to the new object in.
#
#	The resetter deletes all attributes, this can be used to replace
#	an object. The resetter is called this way:
#		$reference.reset
#
#	The destructor can be called in the following way:
#		$reference.delete
#	This will destroy all methods and attributes.
#
#	A getter takes the name of the variable to store the value in as the
#	first argument, if this is ommitted, the value is written to stdout.
#
#	The copy method can be used to create a shallow copy of an object.
#
# @param bsda_obj_namespace
#	The frameowrk namespace to use when building a class. The impact is on
#	the use of helper functions.
# @return
#	0 on succes
#	1 if there is more than one init method (i:) specified
#	2 if there is more than one cleanup method (c:) specified
#	3 if there was an unknown scope operator
#	4 for an attempt to extend something that is not a class
#	5 for an attempt to implement something that is not an interface
#
bsda:obj:createClass() {
	local IFS class methods method attributes getters setters arg
	local getter setter attribute reference init clean serialise extends
	local implements
	local namespacePrefix classPrefix prefix
	local superInit superClean superInitParent superCleanParent
	local inheritedAttributes inheritedMethods parent parents
	local previousMethod scope interface

	# Default framework namespace.
	: ${bsda_obj_namespace='bsda:obj'}

	# Get the class name and shift it off the parameter list.
	class="$1"
	shift

	IFS='
'

	# There are some default methods.
	methods="reset${IFS}delete${IFS}copy${IFS}serialise${IFS}serialiseDeep"
	attributes=
	getters=
	setters=
	init=
	clean=
	extends=
	implements=
	superInit=
	superClean=

	# Parse arguments.
	for arg in "$@"; do
		case "$arg" in
			x:*)
				methods="$methods${methods:+$IFS}${arg#x:}"
			;;
			-:*)
				attributes="$attributes${attributes:+$IFS}${arg#-:}"
			;;
			r:*)
				attributes="$attributes${attributes:+$IFS}${arg##*:}"
				getters="$getters${getters:+$IFS}${arg#r:}"
			;;
			w:*)
				attributes="$attributes${attributes:+$IFS}${arg##*:}"
				getters="$getters${getters:+$IFS}${arg#w:}"
				setters="$setters${getters:+$IFS}${arg#w:}"
			;;
			i:*)
				if [ -n "$init" ]; then
					echo "bsda:obj:createClasss: ERROR: More than one init method was supplied!" 1>&2
					return 1
				fi
				methods="$methods${methods:+$IFS}${arg#i:}"
				init="$class.${arg##*:}"
			;;
			c:*)
				if [ -n "$clean" ]; then
					echo "bsda:obj:createClasss: ERROR: More than one cleanup method was supplied!" 1>&2
					return 2
				fi
				methods="$methods${methods:+$IFS}${arg#c:}"
				clean="$class.${arg##*:}"
			;;
			extends:*)
				extends="$extends${extends:+$IFS}${arg#extends:}"
			;;
			implements:*)
				implements="$implements${implements:+$IFS}${arg#implements:}"
			;;
			*)
				# Assume everything else is a comment.
			;;
		esac
	done

	# Create reference prefix. The Process id is added to the prefix when
	# an object is created.
	namespacePrefix="${bsda_obj_frameworkPrefix}$(echo "$bsda_obj_namespace" | tr ':' '_')_"
	classPrefix="${namespacePrefix}$(echo "$class" | tr ':' '_')_"

	# Set the instance match pattern.
	setvar ${classPrefix}instancePatterns "${classPrefix}[0-9a-f]+_[0-9]+_[0-9]+_[0-9]+_"

	# Create getters.
	for method in $getters; do
		getter="${method##*:}"
		attribute="$getter"
		getter="get$(echo "${getter%%${getter#?}}" | tr '[:lower:]' '[:upper:]')${getter#?}"

		eval "
			$class.$getter() {
				if [ -n \"\$1\" ]; then
					eval \"\$1=\\\"\\\$\${this}$attribute\\\"\"
				else
					eval \"echo \\\"\\\$\${this}$attribute\\\"\"
				fi
			}
		"

		# Check for scope operator.
		if [ "${method%:*}" != "$method" ]; then
			# Add scope operator to the getter name.
			getter="${method%:*}:$getter"
		fi
		# Add the getter to the list of methods.
		methods="$methods${methods:+$IFS}${getter}"
	done

	# Create setters.
	for method in $setters; do
		setter="${method##*:}"
		attribute="$setter"
		setter="set$(echo "${setter%%${setter#?}}" | tr '[:lower:]' '[:upper:]')${setter#?}"

		eval "
			$class.$setter() {
				setvar \"\${this}$attribute\" \"\$1\"
			}
		"

		# Check for scope operator.
		if [ "${method%:*}" != "$method" ]; then
			# Add scope operator to the getter name.
			setter="${method%:*}:$setter"
		fi
		# Add the setter to the list of methods.
		methods="$methods${methods:+$IFS}$setter"
	done

	# Add implicit public scope to methods.
	method="$methods"
	methods=
	for method in $method; do
		# Check the scope.
		case "${method%:*}" in
			$method)
				# There is no scope operator, add public.
				methods="${methods:+$methods$IFS}public:$method"
			;;
			public | protected | private)
				# The accepted scope operators.
				methods="${methods:+$methods$IFS}$method"
			;;
			*)
				# Everything else is not accepted.
				echo "bsda:obj:createClasss: ERROR: Unknown scope operator \"${method%:*}\"!" 1>&2
				return 3
			;;
		esac
	done

	# Manage inheritance.
	superInit=
	superClean=
	for parent in $extends; do
		if ! $parent.isClass; then
			echo "bsda:obj:createClasss: ERROR: Extending \"$parent\" failed, not a class!" 1>&2
			return 4
		fi

		# Get the interfaces implemented by the class.
		# Filter already registered interfaces.
		parents="$($parent.getInterfaces | /usr/bin/grep -vFx "$implements")"
		# Append the detected interfaces to the list of implemented
		# interfaces.
		implements="$implements${implements:+${parents:+$IFS}}$parents"

		# Get the parents of this class.
		# Filter already registered parents.
		parents="$($parent.getParents | /usr/bin/grep -vFx "$extends")"
		# Append the detected parents to the list of extended classes.
		extends="$extends${parents:+$IFS$parents}"

		# Get the super methods, first class wins.
		if [ -z "$superInit" ]; then
			$parent.getInit superInit
			superInitParent=$parent
		fi
		if [ -z "$superClean" ]; then
			$parent.getClean superClean
			superCleanParent=$parent
		fi

		# Get inherited methods and attributes.
		inheritedMethods="$($parent.getMethods | /usr/bin/grep -vFx "$methods")"
		inheritedAttributes="$($parent.getAttributes | /usr/bin/grep -vFx "$attributes")"

		# Update the list of attributes.
		attributes="$inheritedAttributes${inheritedAttributes:+${attributes:+$IFS}}$attributes"

		# Create aliases for methods.
		for method in $inheritedMethods; do
			# Check whether this method already exists with a
			# different scope.
			if echo "$methods" | /usr/bin/grep -qx ".*:${method##*:}"; then
				# Skip ahead.
				continue
			fi

			# Inherit method.
			# Alias does not work in bash unless interactve
			#alias $class.${method##*:}=$parent.${method##*:}
			eval "$class.${method##*:}() { $parent.${method##*:} \"\$@\"; }"
		done

		# Update the list of methods.
		methods="$inheritedMethods${inheritedMethods:+${methods:+$IFS}}$methods"

		# Update the instance match patterns of parents.
		for parent in $parent${parents:+$IFS$parents}; do
			$parent.getPrefix parent
			eval "${parent}instancePatterns=\"\${${parent}instancePatterns}|\${${classPrefix}instancePatterns}\""
		done
	done


	# Get the super methods, first class wins.
	test -z "$init" -a -n "$superInit" && init="$superInit"
	test -z "$clean" -a -n "$superClean" && clean="$superClean"

	# Manage implements.
	for interface in $implements; do
		if ! $interface.isInterface; then
			echo "bsda:obj:createClasss: ERROR: Implementing \"$interface\" failed, not an interface!" 1>&2
			return 5
		fi

		# Get the parents of this interface.
		# Filter already registered parents.
		parents="$($interface.getParents | /usr/bin/grep -vFx "$implements")"
		# Append the detected parents to the list of extended classes.
		implements="$implements${parents:+$IFS$parents}"

		# Get inherited public methods.
		inheritedMethods="$($interface.getMethods | /usr/bin/grep -vFx "$methods")"

		# Update the list of methods.
		methods="$inheritedMethods${inheritedMethods:+${methods:+$IFS}}$methods"

		# Update the instance match patterns of parents.
		for parent in $interface${parents:+$IFS$parents}; do
			$parent.getPrefix parent
			eval "${parent}instancePatterns=\"\${${parent}instancePatterns:+\${${parent}instancePatterns}|}\${${classPrefix}instancePatterns}\""
		done
	done

	# If a method is defined more than once, the widest scope wins.
	# Go through the methods sorted by method name.
	previousMethod=
	method="$methods"
	methods=
	scope=
	for method in $(echo "$method" | /usr/bin/sort -t: -k2); do
		# Check whether the previous and the current method were the
		# same.
		if [ "$previousMethod" != "${method##*:}" ]; then
			# If all scopes of this method have been found,
			# store it in the final list.
			methods="${methods:+$methods${previousMethod:+$IFS}}${previousMethod:+$scope:$previousMethod}"
			scope="${method%:*}"
		else
			# Widen the scope if needed.
			case "${method%:*}" in
				public)
					scope=public
				;;
				protected)
					if [ "$scope" = "private" ]; then
						scope=protected
					fi
				;;
			esac
		fi

		previousMethod="${method##*:}"
	done
	# Add the last method (this never happens in the loop).
	methods="${methods:+$methods${previousMethod:+$IFS$scope:$previousMethod}}"

	#
	# Store access scope checks for each scope in the class context.
	# Note that at the time this is run the variables class and this
	# still belong to the the caller.
	# These definitions are repeatedly subject to eval calls, hence
	# the different escape depth which makes sure the variables
	# are resolved at the right stage.
	#

	# Private methods allow the following kinds of access:
	# - Same class
	#   Access is allowed by all objects with the same class.
	#   This excludes inheriting classes.
	setvar ${classPrefix}private "
		if [ \\\"\\\$class\\\" != \\\"$class\\\" ]; then
			echo \\\"$class.\${method##*:}(): Terminated because of access attempt to a private method\\\${class:+ by \\\$class}!\\\" 1>&2
			return 255
		fi
	"
	# Protected methods allow the following kinds of access:
	# - Derived classes
	#   Access is allowed to instances of the same class and its
	#   decendants.
	# - Parent classes
	#   Access is permitted to all parent classes.
	# - Namespace
	#   Access is allowed from the same namespace or subspaces of the
	#   own namespace. Classes without a namespace cannot access each
	#   other this way.
	setvar ${classPrefix}protected "
		if (! $class.isInstance \\\$this) && (! echo \\\"\\\$class\\\" | /usr/bin/grep -Fx '$extends' > /dev/null) && [ \\\"\\\${class#${class%:*}}\\\" = \\\"\\\$class\\\" ]; then
			echo \\\"$class.\${method##*:}(): Terminated because of access attempt to a protected method\\\${class:+ by \\\$class}!\\\" 1>&2
			return 255
		fi
	"
	# Public methods allow unchecked access.
	setvar ${classPrefix}public ''

	# Create constructor.
	eval "
		$class() {
			local _return this class
			class=$class

			eval \"
				# Create object reference.
				this=\\\"${classPrefix}\${bsda_obj_uid}_\\\${${classPrefix}\${bsda_obj_uid}_nextId:-0}_\\\"
	
				# Increase the object id counter.
				${classPrefix}\${bsda_obj_uid}_nextId=\\\$((\\\$${classPrefix}\${bsda_obj_uid}_nextId + 1))
			\"

			# Create method instances.
			$bsda_obj_namespace:createMethods $class $classPrefix \$this \"$methods\"

			# Return the object reference.
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" \$this
			else
				echo \$this
			fi

			${clean:+
				bsda_obj_freeOnExit=\"\${bsda_obj_freeOnExit:+\${bsda_obj_freeOnExit\}$IFS\}\$this\"
			}

			# If this object construction is part of a copy() call,
			# this constructor is done.
			test -n \"\$bsda_obj_doCopy\" && return 0

			${init:+
				# Cast the reference variable from the parameters.
				shift
				# Call the init method.
				$init \"\$@\"
				_return=\$?
				# Destroy the object on failure.
				test \$_return -ne 0 && \$this.delete
				return \$_return
			}

			# Only if no init method is given.
			return 0
		}
	"

	# Create a resetter.
	eval "
		$class.reset() {
			${clean:+$clean \"\$@\" || return}

			# Delete attributes.
			$bsda_obj_namespace:deleteAttributes \$this \"$attributes\"
		}
	"

	# Create destructor.
	eval "
		$class.delete() {
			${clean:+
				$clean \"\$@\" || return
				# Unregister cleanup function from EXIT trap
				local nl head tail
				nl='
'
				tail=\"\${bsda_obj_freeOnExit#*\$this\}\"
				tail=\"\${tail#\$nl\}\"
				head=\"\${bsda_obj_freeOnExit%\$this*\}\"
				head=\"\${head%\$nl\}\"
				bsda_obj_freeOnExit=\"\$head\${head:+\${tail:+\$nl\}\}\$tail\"
			}

			# Delete methods and attributes.
			$bsda_obj_namespace:deleteMethods \$this \"$methods\"
			$bsda_obj_namespace:deleteAttributes \$this \"$attributes\"
		}
	"

	# Create copy method.
	eval "
		$class.copy() {
			local IFS bsda_obj_doCopy reference attribute

			bsda_obj_doCopy=1
			IFS='
'

			# Create a new empty object.
			$class reference

			# Store the new object reference in the target variable.
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" \$reference
			else
				echo \$reference
			fi

			# For each attribute copy the value over to the
			# new object.
			for attribute in \$(echo \"$attributes\"); do
				eval \"\$reference\$attribute=\\\"\\\$\${this}\$attribute\\\"\"
			done
		}
	"

	# A serialise method.
	eval "
		$class.serialise() {
			local IFS attribute serialised

			IFS='
'

			serialised=
			for attribute in \$(echo '$attributes'); do
				serialised=\"\${serialised:+\$serialised;}\${this}\$attribute=\\\"\$(
					eval \"echo -n \\\"\\\${\${this}\$attribute}\\\"\" | /usr/bin/awk 'BEGIN {ORS = \"\${IFS}\"} nl++ {print \"\"} {gsub(/\\\\/, \"\\\\\\\\\");gsub(/\\\$/, \"\\\\\$\");gsub(/\"/, \"\\\\\\\"\");printf}'
				)\\\"\"
			done
			serialised=\"\$serialised;$class.deserialise \$this\"

			\$caller.setvar \"\$1\" \"\$serialised\"
		}
	"

	# A recursive serialise method.
	eval "
		$class.serialiseDeep() {
			local IFS rootCall objects object serialised attribute

			serialised=
			rootCall=
			IFS='
'

			# Check whether this is the root call.
			if [ -z \"\$bsda_obj_serialiseBlacklist\" ]; then
				rootCall=1
			fi

			# Add this to the blacklist to prevent circular
			# recursion.
			bsda_obj_serialiseBlacklist=\"\${bsda_obj_serialiseBlacklist:+\$bsda_obj_serialiseBlacklist$IFS}\$this\"

			# Create a list of all referenced objects.
			objects=\"\$(
				# Echo each attribute.
				for attribute in \$(echo '$attributes'); do
					eval \"echo \\\"\\\${\$this\$attribute}\\\"\"
				done | /usr/bin/egrep -o '$bsda_obj_frameworkPrefix[_[:alnum:]]+_[0-9a-f]+_[0-9]+_[0-9]+_[0-9]+_' | /usr/bin/grep -vFx \"\$bsda_obj_serialiseBlacklist\" | /usr/bin/sort -u
			)\"

			# Serialize all required objects.
			for object in \$objects; do
				\$object.serialiseDeep 2> /dev/null \
					|| echo \"$class.serialiseDeep: WARNING: Missing object \\\"\$object\\\" referenced by \\\"\$this\\\"!\" 1>&2
			done

			# Serialize this.
			\$this.serialise serialised

			# Append this to the recursive serialisation list.
			bsda_obj_serialised=\"\${bsda_obj_serialised:+\$bsda_obj_serialised$IFS}\$serialised\"

			# Root call only.
			if [ -n \"\$rootCall\" ]; then
				# Return serialised string.
				\$caller.setvar \"\$1\" \"\$bsda_obj_serialised\"
				# Wipe static serialisation variables.
				unset bsda_obj_serialised
				unset bsda_obj_serialiseBlacklist
			fi
			return 0
		}
	"

	# A static super method, which calls the init method of the
	# parent class.
	eval "
		$class.superInit() {
			${superInit:+$superInit \"\$@\"}
			return
		}
	"

	# A static super method, which calls the cleanup method of the
	# parent class.
	eval "
		$class.superClean() {
			${superClean:+$superClean \"\$@\"}
			return
		}
	"

	# A static deserialise method.
	eval "
		$class.deserialise() {
			# Create method instances.
			$bsda_obj_namespace:createMethods $class $classPrefix \$1 \"$methods\"
		}
	"

	# A static type checker.
	eval "
		$class.isInstance() {
			echo \"\$1\" | /usr/bin/egrep -xq \"\${${classPrefix}instancePatterns}\"
		}
	"

	# Return whether this is a class.
	eval "
		$class.isClass() {
			return 0
		}
	"

	# Return whether this is an interface.
	eval "
		$class.isInterface() {
			return 1
		}
	"

	# A static method that returns the attributes of a class.
	eval "
		$class.getAttributes() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$attributes'
			else
				echo '$attributes'
			fi
		}
	"

	# A static method that returns the methods of a class.
	eval "
		$class.getMethods() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$methods'
			else
				echo '$methods'
			fi
		}
	"

	# A static method that returns the class prefix.
	eval "
		$class.getPrefix() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$classPrefix'
			else
				echo '$classPrefix'
			fi
		}
	"

	# A static method that returns the parentage of this class.
	eval "
		$class.getInterfaces() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$implements'
			else
				echo '$implements'
			fi
		}
	"

	# A static method that returns the parentage of this class.
	eval "
		$class.getParents() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$extends'
			else
				echo '$extends'
			fi
		}
	"

	# A static method that returns the name of the init method.
	eval "
		$class.getInit() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$init'
			else
				echo '$init'
			fi
		}
	"

	# A static method that returns the name of the cleanup method.
	eval "
		$class.getClean() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$clean'
			else
				echo '$clean'
			fi
		}
	"
}

#
# This function creates an interface that can be implemented by a class.
#
# It is similar to the bsda:obj:createClass() function, but a lot less complex.
#
# The following static methods are reserved:
#	isInstance()
#	isClass()
#	isInterface()
#	getMethods()
#	getPrefix()
#	getParents()
#
# The following class prefix bound static attributes are reserved:
#	instancePatterns
#
# @param 1
#	The first parameter is the name of the interface.
# @param @
#	A description of the interface to create.
#
#	All parameters following the interface name make up a list of
#	identifiers, the different types of identifiers are distinguished by
#	the following prefixes:
#
#		x: Defines a public method.
#		extends:
#		   This prefix is followed by the name of another interface
#		   from which method definitions are inherited.
#
#	Everything that is not recognized as an identifier is treated as a
#	comment.
#
# @param bsda_obj_namespace
#	The frameowrk namespace to use when building a class. The impact is on
#	the use of helper functions.
# @return
#	0 on succes
#	1 for an attempt to extend something that is not an interface
#
bsda:obj:createInterface() {
	local IFS arg interface methods extends
	local interfacePrefix namespacePrefix parent parents
	local inheritedMethods

	# Default framework namespace.
	: ${bsda_obj_namespace='bsda:obj'}

	# Get the interface name and shift it off the parameter list.
	interface="$1"
	shift

	IFS='
'

	methods=
	extends=

	# Parse arguments.
	for arg in "$@"; do
		case "$arg" in
			x:*)
				methods="$methods${methods:+$IFS}public:${arg#x:}"
			;;
			extends:*)
				extends="$extends${extends:+$IFS}${arg#extends:}"
			;;
			*)
				# Assume everything else is a comment.
			;;
		esac
	done

	# Create an interface prefix, this is required to access the instance
	# matching patterns.
	namespacePrefix="${bsda_obj_frameworkPrefix}$(echo "$bsda_obj_namespace" | tr ':' '_')_"
	interfacePrefix="${namespacePrefix}$(echo "$interface" | tr ':' '_')_"

	# Set the instance match pattern.
	setvar ${interfacePrefix}instancePatterns "${interfacePrefix}[0-9a-f]+_[0-9]+_[0-9]+_[0-9]+_"

	# Manage inheritance.
	for parent in $extends; do
		if ! $parent.isInterface; then
			echo "bsda:obj:createInterface: ERROR: Extending \"$interface\" failed, not an interface!" 1>&2
			return 1
		fi


		# Get the parents of this interface.
		# Filter already registered parents.
		parents="$($parent.getParents | /usr/bin/grep -vFx "$extends")"
		# Append the detected parents to the list of extended interfaces.
		extends="$extends${parents:+$IFS$parents}"

		# Get inherited public methods.
		inheritedMethods="$($parent.getMethods | /usr/bin/grep -vFx "$methods")"

		# Update the list of methods.
		methods="$inheritedMethods${inheritedMethods:+${methods:+$IFS}}$methods"

		# Update the instance match patterns of parents.
		for parent in $parent${parents:+$IFS$parents}; do
			$parent.getPrefix parent
			eval "${parent}instancePatterns=\"\${${parent}instancePatterns}|\${${interfacePrefix}instancePatterns}\""
		done
	done

	# A static type checker.
	eval "
		$interface.isInstance() {
			echo \"\$1\" | /usr/bin/egrep -xq \"\${${interfacePrefix}instancePatterns}\"
		}
	"

	# Return whether this is a class.
	eval "
		$interface.isClass() {
			return 1
		}
	"

	# Return whether this is an interface.
	eval "
		$interface.isInterface() {
			return 0
		}
	"

	# A static method that returns the methods declared in this interace.
	eval "
		$interface.getMethods() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$methods'
			else
				echo '$methods'
			fi
		}
	"

	# A static method that returns the interface prefix.
	eval "
		$interface.getPrefix() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$interfacePrefix'
			else
				echo '$interfacePrefix'
			fi
		}
	"

	# A static method that returns the parentage of this interface.
	eval "
		$interface.getParents() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$extends'
			else
				echo '$extends'
			fi
		}
	"
}

#
# Returns a variable from a given reference. The variable is either written
# to a named variable, or in absence of one, output to stdout.
#
# @param 1
#	If this is the sole parameter it is a reference to the variable
#	to output to stdout. If a second parameter exists, it is the name of
#	the variable to write to.
# @param 2
#	The reference to the variable to return.
#
bsda:obj:getVar() {
	if [ -n "$2" ]; then
		eval "$1=\"\$$2\""
	else
		eval "echo \"\$$1\""
	fi
}

#
# Returns an object reference to a serialised object.
#
# @param 1
#	If this is the sole parameter, this is a serialised string of which
#	the object reference should be output. In case of a second parameter
#	this is the name of the variable to return the reference to the
#	serialised object to.
# @param 2
#	The serialised string of which the reference should be returned.
#	
bsda:obj:getSerializedId() {
	if [ -n "$2" ]; then
		setvar "$1" "${2##* }"
	else
		echo "${1##* }"
	fi
}

#
# Deserialises a serialised object and returns or outputs a reference to
# said object.
#
# @param &1
#	The name of the variable to store the deserialised object reference
#	in. If empty the reference will be output to stdout.
# @param 2
#	If given this is the string to be serialised, otherwise it will be
#	expected on stdin.
#
bsda:obj:deserialise() {
	if [ $# -lt 2 ]; then
		set -- "$1" "$(/bin/cat)"
	fi

	if [ -n "$1" ]; then
		setvar "$1" "${2##* }"
	else
		echo "${2##* }"
	fi

	local IFS
	IFS='
'
	eval "$2"
}

#
# Filters the given string of serialised data to only contain the last
# representation of each object.
#
# The order of objects may be subject to change.
#
# @param &1
#	The name of the variable to store the resulting string in.
#	If empty the string is output to stdout.
# @param 2
#	If given this is the serialised data, otherwise it will be
#	expected on stdin.
#
bsda:obj:serialisedUniq() {
	if [ -n "$1" ]; then
		if [ -n "$2" ]; then
			setvar "$1" "$(echo "$2" | /usr/bin/awk '{lines[$NF] = $0} END {for (line in lines) print lines[line]}')"
		else
			setvar "$1" "$(/usr/bin/awk '{lines[$NF] = $0} END {for (line in lines) print lines[line]}')"
		fi
	else
		if [ -n "$2" ]; then
			echo "$2" | /usr/bin/awk '{lines[$NF] = $0} END {for (line in lines) print lines[line]}'
		else
			/usr/bin/awk '{lines[$NF] = $0} END {for (line in lines) print lines[line]}'
		fi
	fi
}

#
# Checks whether the given parameter is an object.
#
# @param 1
#	The parameter to check.
# @return
#	0 for objects, 1 for everything else.
#
bsda:obj:isObject() {
	echo "$1" | /usr/bin/egrep -qxe "$bsda_obj_frameworkPrefix[_[:alnum:]]+_[0-9a-f]+_[0-9]+_[0-9]+_[0-9]+_"
}

#
# Checks whether the given parameter is an integer.
# Integers may be signed, but there must not be any spaces.
#
# @param 1
#	The parameter to check.
# @return
#	0 for integers, 1 for everything else.
#
bsda:obj:isInt() {
	echo "$1" | /usr/bin/egrep -qxe "[-+]?[0-9]+"
}

#
# Checks whether the given parameter is an unsigned integer.
#
# @param 1
#	The parameter to check.
# @return
#	0 for unsigned integers, 1 for everything else.
#
bsda:obj:isUInt() {
	echo "$1" | /usr/bin/egrep -qxe "\+?[0-9]+"
}

#
# Checks whether the given parameter is a floating point value.
# Floats may be signed, but there must not be any spaces.
# This function does not obey the locale.
#
# The following are examples for valid floats:
#	1
#	1.0
#	-1.5
#	1000
#	1e3	= 1000
#	1e-3	= 0.001
#	-1e-1	= -0.1
#	+1e+2	= 100
#
# @param 1
#	The parameter to check.
# @return
#	0 for floats, 1 for everything else.
#
bsda:obj:isFloat() {
	echo "$1" | /usr/bin/egrep -qxe "[-+]?[0-9]+(\.[0-9]+)?(e(-|\+)?[0-9]+)?"
}

#
# Checks whether the given parameter is a simple floating point value.
# Simple floats may be signed, but there must not be any spaces.
# This function does not obey the locale.
#
# The following are examples for valid simple floats:
#	1
#	1.0
#	-1.5
#	1000
#
# @param 1
#	The parameter to check.
# @return
#	0 for simple floats, 1 for everything else.
#
bsda:obj:isSimpleFloat() {
	echo "$1" | /usr/bin/egrep -qxe "[-+]?[0-9]+(\.[0-9]+)?"
}

#
# Creates the methods to a new object from a class.
#
# This is achieved by creating a method wrapper that provides the
# context variables this, class and caller.
#
# It works under the assumption, that methods are defined as:
#	<class>.<method>()
#
# @param 1
#	The class name.
# @param 2
#	The class prefix where the scope checks are stored.
# @param 3
#	The object reference.
# @param 4
#	A list of method names.
#
if [ -z "$BSDA_OBJ_NOSCOPE" ]; then
	# Use the regular implementation.
	bsda:obj:createMethods() {
		local method scope
		for method in $4; do
			scope=${method%:*}
			# Get scope check from class.
			eval "scope=\"\$$2$scope\""
			# Add method name to scope.
			eval "scope=\"$scope\""
			method=${method##*:}
			eval "
				$3.$method() {
					$scope
					local caller
					bsda:obj:callerSetup
					local class this _return
					class=$1
					this=$3
					$1.$method \"\$@\"
					_return=\$?
					bsda:obj:callerFinish
					return \$_return
				}
			"
		done
	}
else
	# Use the implementation without scope checks.
	bsda:obj:createMethods() {
		local method
		for method in $4; do
			method=${method##*:}
			eval "
				$3.$method() {
					local caller
					bsda:obj:callerSetup
					local class this _return
					class=$1
					this=$3
					$1.$method \"\$@\"
					_return=\$?
					bsda:obj:callerFinish
					return \$_return
				}
			"
		done
	}
fi

#
# Deletes methods from an object. This is intended to be used in a destructor.
#
# @param 1
#	The object reference.
# @param 2
#	A list of method names.
#
bsda:obj:deleteMethods() {
	local method
	for method in $2; do
		method=${method##*:}
		unset -f "$1.$method"
	done
}

#
# Deletes attributes from an object. This is intended to be used in a
# destructor.
#
# This works under the assumption, that attributes are defined as:
#	<reference>_<attribute>
#
# @param 1
#	The object reference.
# @param 2
#	A list of attribute names.
#
bsda:obj:deleteAttributes() {
	local attribute
	for attribute in $2; do
		unset "${1}$attribute"
	done
}

#
# Setup the caller stack to store variables that should be overwritten
# in the caller context upon exiting the method.
#
# This function is called by the wrapper around class instance methods.
#
# The bsda_obj_callStackCount counter is increased and and a stack count prefix
# is created, which is used by bsda:obj:callerSetvar() to store variables
# for functions in the caller context until bsda:obj:callerFinish() is
# called.
#
# The call stack prefix is in the format 'bsda_obj_callStack_[0-9]+_'.
#
# @param caller
#	Is set to the current stack count prefix.
# @param bsda_obj_callStackCount
#	Is incremented by 1 and used to create the caller variable.
#
bsda:obj:callerSetup() {
	# Increment the call stack counter and create the caller prefix.
	caller="bsda_obj_callStack_${bsda_obj_callStackCount}_"
	bsda_obj_callStackCount=$(($bsda_obj_callStackCount + 1))

	# Create functions to interact with the caller.
	eval "
		# Create a wrapper around bsda:obj:callerSetvar for access
		# through the caller prefix. I do not have the slightest idea
		# why alias does not work for this.
		$caller.setvar() {
			bsda:obj:callerSetvar \"\$@\"
		}

		# Create a function that returns the object ID of the caller.
		$caller.getObject() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$this'
			else
				echo '$this'
			fi
		}

		# Create a function that returns the class of the caller.
		$caller.getClass() {
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" '$class'
			else
				echo '$class'
			fi
		}
	"

}

#
# Copy variables from the caller stack into the caller context and clean
# the stack up.
#
# This function is called by the wrapper around class instance methods
# after the actual method has terminated.
#
# @param caller
#	The caller context prefix.
# @param ${caller}_setvars
#	The list of variables to copy into the caller context.
# @param bsda_obj_callStackCount
#	Is decremented by 1.
#
bsda:obj:callerFinish() {
	# Remove the bsda:obj:callerSetvar() wrapper.
	unset -f $caller.setvar $caller.getObject $caller.getClass
	# Decrement the call stack counter.
	bsda_obj_callStackCount=$(($bsda_obj_callStackCount - 1))

	# Copy variables to the caller context.
	local _var IFS
	IFS=' '
	eval "_var=\"\$${caller}_setvars\""
	for _var in $_var; do
		# Copy variable.
		eval "setvar $_var \"\$$caller$_var\""
		# Delete variable from stack.
		unset $caller$_var
	done
	# Delete list of variables from stack.
	unset ${caller}_setvars
}

#
# This function stores a variables for overwriting variables in the context
# of the caller. If no storing variable has been specified (i.e. the first
# parameter is empty), the value is printed instead.
#
# This function is accessable in methods by calling:
#	$caller.setvar
#
# The stored variables are processed by the bsda:obj:callerFinish() function.
#
# @param 1
#	The name of the variable to store.
# @param 2
#	The value to store.
# @param caller
#	The context to store variables in.
# @param ${caller}_setvars
#	A list of all the stored variables for the caller context.
#
bsda:obj:callerSetvar() {
	# Print if no return variable was specified.
	test -z "$1" && echo "$2" && return

	# Store value.
	setvar $caller$1 "$2"
	# Register variable.
	eval "${caller}_setvars=\$${caller}_setvars\${${caller}_setvars:+ }$1"
}

#
# This function can be used to update bsda_obj_uid in forked processes.
#
# This is necessary when both processes exchange objects (commonly in
# serialised form) and thus need to be able to create objects with unique
# IDs.
#
# The function should be called within the forked process without parameters.
#
# @param bsda_obj_uid
#	Is set to a new uid
# @param bsda_obj_freeOnExit
#	The list of objects to garbage collect when terminating
#
bsda:obj:fork() {
	# Reset resource collection
	bsda_obj_freeOnExit=
	trap bsda:obj:exit EXIT
	trap "bsda:obj:exit;exit" INT TERM

	# Update UID
	bsda_obj_uid="$(/bin/uuidgen | /usr/bin/tr '-' '_')"
}

#
# This function calls all delete functions of objects having a cleanup
# method.
#
# @param bsda_obj_freeOnExit
#	The list of objects to call
#
bsda:obj:exit() {
	# Wait for children to terminate first to ensure they do not use
	# resources that are about to be freed.
	wait
	local nl obj
	nl='
'
	while [ -n "$bsda_obj_freeOnExit" ]; do
		obj="${bsda_obj_freeOnExit%%$nl*}"
		if ! $obj.delete; then
			echo "bsda:obj:exit: WARNING: Delete of $obj failed!" 1>&2
			local head tail
			tail="${bsda_obj_freeOnExit#*$obj}"
			tail="${tail#$nl}"
			head="${bsda_obj_freeOnExit%$this*}"
			head="${head%$nl}"
			bsda_obj_freeOnExit="$head${head:+${tail:+$nl}}$tail"
		fi
	done
}

#
# Initialise session UID and garbage collection.
#
bsda:obj:fork

#
# Hacks.
#

#
# Ignore nullptr delete.
#
.delete() {
	: # bash hack
}

#
# Compatibility hacks.
#

# Emulate setvar for shells that don't have it, i.e. bash.
if ! setvar 2> /dev/null; then
	setvar() {
		eval "$1=\"\$2\""
	}
fi

