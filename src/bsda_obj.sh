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
test -n "$_bsda_obj_" && return 0
readonly _bsda_obj_=1
set -f

#
# This file contains helper functions for creating object oriented
# shell scripts.
#
# The most significant function is bsda:obj:createClass(), which basically
# creates a class, including getters, setters, a constructor, a destructor,
# a reset and a copy function. It also creates serialisation methods.
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
# A list of available file descriptors for bsda:obj:getDesc().
#
bsda_obj_desc=3,4,5,6,7,8,9,

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
	methods="reset${IFS}delete${IFS}copy${IFS}serialise${IFS}serialiseDeep${IFS}"
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
				methods="$methods${arg#x:}$IFS"
			;;
			-:*)
				attributes="$attributes${arg#-:}$IFS"
			;;
			r:*)
				attributes="$attributes${arg##*:}$IFS"
				getters="$getters${arg#r:}$IFS"
			;;
			w:*)
				attributes="$attributes${arg##*:}$IFS"
				getters="$getters${arg#w:}$IFS"
				setters="$setters${arg#w:}$IFS"
			;;
			i:*)
				if [ -n "$init" ]; then
					echo "bsda:obj:createClasss: ERROR: More than one init method was supplied!" 1>&2
					return 1
				fi
				methods="$methods${arg#i:}$IFS"
				init="$class.${arg##*:}"
			;;
			c:*)
				if [ -n "$clean" ]; then
					echo "bsda:obj:createClasss: ERROR: More than one cleanup method was supplied!" 1>&2
					return 2
				fi
				methods="$methods${arg#c:}$IFS"
				clean="$class.${arg##*:}"
			;;
			extends:*)
				extends="$extends${arg#extends:}$IFS"
			;;
			implements:*)
				implements="$implements${arg#implements:}$IFS"
			;;
			*)
				# Assume everything else is a comment.
			;;
		esac
	done

	# Create reference prefix. The Process id is added to the prefix when
	# an object is created.
	namespacePrefix="${bsda_obj_frameworkPrefix}$(echo "$bsda_obj_namespace" | /usr/bin/tr ':' '_')_"
	classPrefix="${namespacePrefix}$(echo "$class" | /usr/bin/tr ':' '_')_"

	# Set the instance match pattern.
	setvar ${classPrefix}instancePatterns "${classPrefix}([0-9a-f]+_){5}[0-9]+_$IFS"

	# Create getters.
	for method in $getters; do
		getter="${method##*:}"
		attribute="$getter"
		getter="get$(echo "${getter%%${getter#?}}" | /usr/bin/tr '[:lower:]' '[:upper:]')${getter#?}"

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
		methods="$methods$getter$IFS"
	done

	# Create setters.
	for method in $setters; do
		setter="${method##*:}"
		attribute="$setter"
		setter="set$(echo "${setter%%${setter#?}}" | /usr/bin/tr '[:lower:]' '[:upper:]')${setter#?}"

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
		methods="$methods$setter$IFS"
	done

	# Add implicit public scope to methods.
	method="$methods"
	methods=
	for method in $method; do
		# Check the scope.
		case "${method%:*}" in
			$method)
				# There is no scope operator, add public.
				methods="${methods}public:$method$IFS"
			;;
			public | protected | private)
				# The accepted scope operators.
				methods="$methods$method$IFS"
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
		implements="$implements${parents:+$parents$IFS}"

		# Get the parents of this class.
		# Filter already registered parents.
		parents="$($parent.getParents | /usr/bin/grep -vFx "$extends")"
		# Append the detected parents to the list of extended classes.
		extends="$extends${parents:+$parents$IFS}"

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
		attributes="${inheritedAttributes:+$inheritedAttributes$IFS}$attributes"

		# Create aliases for methods.
		for method in $inheritedMethods; do
			# Check whether this method already exists
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
		methods="${inheritedMethods:+$inheritedMethods$IFS}$methods"

		# Update the instance match patterns of parents.
		for parent in $parent$IFS$parents; do
			$parent.getPrefix parent
			eval "${parent}instancePatterns=\"\${${parent}instancePatterns}\${${classPrefix}instancePatterns}\""
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
		implements="$implements${parents:+$parents$IFS}"

		# Get inherited public methods.
		inheritedMethods="$($interface.getMethods | /usr/bin/grep -vFx "$methods")"

		# Update the list of methods.
		methods="${inheritedMethods:+$inheritedMethods$IFS}$methods"

		# Update the instance match patterns of parents.
		for parent in $interface$IFS$parents; do
			$parent.getPrefix parent
			eval "${parent}instancePatterns=\"\${${parent}instancePatterns}\${${classPrefix}instancePatterns}\""
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
			methods="$methods${previousMethod:+$scope:$previousMethod$IFS}"
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
	methods="$methods${previousMethod:+$scope:$previousMethod$IFS}"

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
				bsda_obj_freeOnExit=\"\$bsda_obj_freeOnExit\$this$IFS\"
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
				local nl
				nl='$IFS'
				bsda_obj_freeOnExit=\"\${bsda_obj_freeOnExit%%\$this*\}\${bsda_obj_freeOnExit#*\$this\$nl\}\"
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
				done | /usr/bin/egrep -o '$bsda_obj_frameworkPrefix[_[:alnum:]]+_([0-9a-f]+_){5}[0-9]+_' | /usr/bin/grep -vFx \"\$bsda_obj_serialiseBlacklist\" | /usr/bin/sort -u
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
				methods="${methods}public:${arg#x:}$IFS"
			;;
			extends:*)
				extends="$extends${arg#extends:}$IFS"
			;;
			*)
				# Assume everything else is a comment.
			;;
		esac
	done

	# Create an interface prefix, this is required to access the instance
	# matching patterns.
	namespacePrefix="${bsda_obj_frameworkPrefix}$(echo "$bsda_obj_namespace" | /usr/bin/tr ':' '_')_"
	interfacePrefix="${namespacePrefix}$(echo "$interface" | /usr/bin/tr ':' '_')_"

	# Set the instance match pattern.
	setvar ${interfacePrefix}instancePatterns "${interfacePrefix}([0-9a-f]+_){5}[0-9]+_$IFS"

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
		extends="$extends${parents:+$parents$IFS}"

		# Get inherited public methods.
		inheritedMethods="$($parent.getMethods | /usr/bin/grep -vFx "$methods")"

		# Update the list of methods.
		methods="${inheritedMethods:+$inheritedMethods$IFS}$methods"

		# Update the instance match patterns of parents.
		for parent in $parent$IFS$parents; do
			$parent.getPrefix parent
			eval "${parent}instancePatterns=\"\${${parent}instancePatterns}\${${interfacePrefix}instancePatterns}\""
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
# Delete all objects in a list of objects.
#
# If deleting an object fails, it has no influence on the subsequent
# deletion of the following objects.
#
# @param @
#	The list of objects
# @return
#	The bitwise OR product of all destructor return values
#
bsda:obj:delete[]() {
	local obj ret
	ret=0
	for obj in "$@"; do
		$obj.delete
		ret=$((ret | $?))
	done
	return $ret
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
	echo "$1" | /usr/bin/egrep -qxe "$bsda_obj_frameworkPrefix[_[:alnum:]]+_([0-9a-f]+_){5}[0-9]+_"

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
		unset -f "$1$method"
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
# Install traps for garbage collection upon termination of the process.
#
bsda:obj:trap() {
	trap bsda:obj:exit EXIT
	trap "bsda:obj:exit;exit" INT TERM
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
	bsda:obj:trap

	# Update UID
	bsda_obj_uid="$(/bin/uuidgen | /usr/bin/tr '-' '_')"
}

#
# This function can be used to detach the script from its execution context.
#
# I.e. it forks and the forked process inherits the responsibilities of
# the main process, while the main process dies.
#
# @warning
#	Detaching the script means loosing the guarantee that resources
#	are freed in order upon termination. It becomes the programmers
#	responsibility to make sure that processes die in the right order.
# @param @
#	The command to detach, treat this like an argument to eval
# @return
#	This function does not return
#
bsda:obj:detach() {
	eval "bsda:obj:trap;" "$@" &
	trap - EXIT
	exit 0
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
			head="${bsda_obj_freeOnExit%%$obj*}"
			tail="${bsda_obj_freeOnExit#*$obj$nl}"
			bsda_obj_freeOnExit="$head$tail"
		fi
	done
}

#
# Returns an exclusive file descriptor number for use.
#
# Note that FreeBSD sh only supports up to 9 file descriptors, so only the 7
# descriptors [3; 9] are available.
#
# @param bsda_obj_desc
#	The list of available file descriptors
# @param &1
#	A reference to the variable that should contain the descriptor number
# @retval 0
#	The descriptor was returned successfully
# @retval 1
#	No more descriptors were available
#
bsda:obj:getDesc() {
	if [ -z "$bsda_obj_desc" ]; then
		return 1
	fi
	# Return first available file descriptor
	setvar $1 ${bsda_obj_desc%%,*}
	# Remove descriptor from the store of available pipes
	bsda_obj_desc=${bsda_obj_desc#*,}
}

#
# Releases an exclusive file descriptor.
#
# Returns a file descriptor back into the pool of usable descriptors.
#
# @param bsda_obj_desc
#	The list of available file descriptors
# @param 1
#	The file descriptor to release
#
bsda:obj:releaseDesc() {
	test -z "$1" && return
	bsda_obj_desc="$bsda_obj_desc$1,"
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
	: # bash does not allow empty functions
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

