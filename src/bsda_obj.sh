test -n "$_bsda_obj_" && return 0
readonly _bsda_obj_=1
set -f

#
# This file contains helper functions for creating object oriented
# shell scripts.
#
# The most significant function is bsda:obj:createClass(), which basically
# creates a class, including getters, setters, a constructor, a destructor
# and a copy function. It also creates serialisation methods.
#

#
# The stack counter that holds the number of methods that currently
# use the return stack.
#
bsda_obj_callStackCount=0

#
# This is a prefix to every object ID.
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
# Creates a new class, i.e. a constructor, destructor, getters, setters
# and so forth.
#
# So all that is left to be done are the methods.
#
# The following static methods are reserved:
# - deserialise()
# - isInstance()
# - isClass()
# - getAttributes()
# - getMethods()
# - getPrefix()
# - getInit()
# - getClean()
#
# The following methods are reserved:
# - copy()
# - delete()
# - serialise()
#
# The following class prefix bound static attributes are reserved:
# - private
# - public
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
#	following formats are supported:
#
#	- `-:<name>`:
#	  A plain attribute.
#	- `r:[<scope>:]<name>`
#	  An attribute with a get method named `$obj.getName()`.
#	- `w:[<scope>:]<name>`
#	  An attribute with a getter and setter named `$obj.getName()`
#	  and `$obj.setName()`.
#	- `x:[<scope>:]<name>`
#	  A user implemented method named `$obj.name()`, needs to
#	  be implemented as 'class.name()`.
#	- `i:[<scope>:]<name>`
#	  An initialisation method called by the constructor. The
#	  scope only affects a direct call of the method, the constructor
#	  is always public.
#	- `c:[<scope>:]<name>`
#	  A cleanup method called by the destructor. The scope only
#	  affects direct calls of the method.
#	- `a:[<scope>:]<name>[=<class>]
#	  An aggregation. Aggregations are special attributes,
#	  referencing other objects, that are automatically
#	  deleted, copied and serialised along with an instance
#	  of a class.
#	  An aggregation attribute has a getter named `$obj.name()`.
#	  An optional class name is used to determine if the default
#	  `$obj.copy()` and `$obj.serialise()` methods can be created.
#	  If the class is omitted, they never are.
#
#	With these parameters a constructor and a destructor will be built.
#	It is important that all used attributes are listed, or the copy,
#	delete and serialisation methods will not work as expected.
#
#	Everything that is not recognized as an identifier is treated as a
#	comment.
#
#	The prefixes r, w, x, i, c and a can be followed by a scope operator
#	public or private.
#
#	The constructor can be called in the following way:
#		<class> <refname>
#	The class name acts as the name of the constructor, <refname> is the
#	name of the variable to store the reference to the new object in.
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
# @retval 0
#	On succes
# @retval 1
#	If there is more than one init method (i:) specified
# @retval 2
#	If there is more than one cleanup method (c:) specified
# @retval 3
#	If there was an unknown scope operator
#
bsda:obj:createClass() {
	local IFS class methods method attributes getters setters arg
	local getter setter attribute init clean
	local namespacePrefix classPrefix instancePattern
	local previousMethod scope
	local aggregations alias classname
	local has_copy has_serialise

	# Default framework namespace.
	: ${bsda_obj_namespace='bsda:obj'}

	# Get the class name and shift it off the parameter list.
	class="$1"
	shift

	IFS='
'

	# There are some default methods.
	methods="delete${IFS}"
	attributes=
	getters=
	setters=
	init=
	clean=
	has_copy=1
	has_serialise=1

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
					echo "bsda:obj:createClass: ERROR: More than one init method was supplied!" 1>&2
					return 1
				fi
				methods="$methods${arg#i:}$IFS"
				init="$class.${arg##*:}"
			;;
			c:*)
				if [ -n "$clean" ]; then
					echo "bsda:obj:createClass: ERROR: More than one cleanup method was supplied!" 1>&2
					return 2
				fi
				methods="$methods${arg#c:}$IFS"
				clean="$class.${arg##*:}"
			;;
			a:*)
				aggregations="$aggregations${arg#a:}$IFS"
			;;
			*)
				# Assume everything else is a comment.
			;;
		esac
	done

	# Create aggregations.
	alias="$aggregations"
	aggregations=
	for alias in $alias; do
		# Get scope of the getter method
		case "$alias" in
		public:* | private:*)
			scope="${alias%%:*}"
			alias="${alias#*:}"
		;;
		*)
			scope=public
		;;
		esac

		# Get alias and class
		case "$alias" in
		*=*)
			classname="${alias#*=}"
			alias="${alias%%=*}"
		;;
		*)
			classname=
		;;
		esac

		aggregations="$aggregations$alias$IFS"
		attributes="$attributes$alias$IFS"
		methods="$methods$scope:$alias$IFS"

		eval "$class.$alias() {
			if [ -n \"\$1\" ]; then
				eval \"\$1=\\\"\\\$\${this}$alias\\\"\"
			else
				eval \"echo \\\"\\\$\${this}$alias\\\"\"
			fi
		}"

		if [ -z "$classname" ]; then
			has_copy=
			has_serialise=
		elif [ "$classname" != "$class" ]; then
			$classname.getMethods \
			| /usr/bin/grep -qFx public:copy || has_copy=
			$classname.getMethods \
			| /usr/bin/grep -qFx public:serialise || has_serialise=
		fi
	done

	# Remove duplicated attributes.
	attributes="$(echo "$attributes" | /usr/bin/awk '!a[$0]++')"

	# Only classes without a custom destructor get copy() and
	# serialise() members.
	if [ -z "$clean" ] && [ -n "$has_copy" ]; then
		methods="${methods}copy${IFS}"
	fi
	if [ -z "$clean" ] && [ -n "$has_serialise" ]; then
		methods="${methods}serialise${IFS}"
	fi

	# Create reference prefix. The Process id is added to the prefix when
	# an object is created.
	namespacePrefix="${bsda_obj_frameworkPrefix}$(echo "$bsda_obj_namespace" | /usr/bin/tr ':' '_')_"
	classPrefix="${namespacePrefix}$(echo "$class" | /usr/bin/tr ':' '_')_"

	# Set the instance match pattern.
	instancePattern="${classPrefix}[0-9a-f]*[0-9]_"

	# Create getters.
	for method in $getters; do
		getter="${method##*:}"
		attribute="$getter"
		getter="get$(echo "${getter%%${getter#?}}" | /usr/bin/tr '[:lower:]' '[:upper:]')${getter#?}"

		eval "$class.$getter() {
			if [ -n \"\$1\" ]; then
				eval \"\$1=\\\"\\\$\${this}$attribute\\\"\"
			else
				eval \"echo \\\"\\\$\${this}$attribute\\\"\"
			fi
		}"

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

		eval "$class.$setter() {
			setvar \"\${this}$attribute\" \"\$1\"
		}"

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
			public | private)
				# The accepted scope operators.
				methods="$methods$method$IFS"
			;;
			*)
				# Everything else is not accepted.
				echo "bsda:obj:createClass: ERROR: Unknown scope operator \"${method%:*}\"!" 1>&2
				return 3
			;;
		esac
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
	setvar ${classPrefix}private "
		if [ \\\"\\\$class\\\" != \\\"$class\\\" ]; then
			echo \\\"$class.\${method##*:}(): Terminated because of access attempt to a private method\\\${class:+ by \\\$class}!\\\" 1>&2
			return 255
		fi
	"
	# Public methods allow unchecked access.
	setvar ${classPrefix}public ''

	# Create constructor.
	eval "$class() {
		local this class
		class=$class

		# Create object reference.
		this=\"${classPrefix}${bsda_obj_uid}_\${${classPrefix}${bsda_obj_uid}_nextId:-0}_\"

		# Increase the object id counter.
		${classPrefix}${bsda_obj_uid}_nextId=\$((\$${classPrefix}${bsda_obj_uid}_nextId + 1))

		# Create method instances.
		$bsda_obj_namespace:createMethods $class $classPrefix \$this \"$methods\"

		${clean:+bsda_obj_freeOnExit=\"\$bsda_obj_freeOnExit\$this$IFS\"}

		# If this object construction is part of a copy() call,
		# this constructor is done.
		if [ -n \"\$bsda_obj_doCopy\" ]; then
			# Return the object reference.
			if [ -n \"\$1\" ]; then
				setvar \"\$1\" \$this
			else
				echo \$this
			fi
			return 0
		fi

		local _return _var
		_var=\"\$1\"
		${init:+
		# Cast the reference variable from the parameters.
		shift
		local caller
		bsda:obj:callerSetup
		# Call the init method.
		$init \"\$@\"
		_return=\$?
		bsda:obj:callerFinish
		# Destroy the object on failure.
		if [ \$_return -ne 0 ]; then
			\$this.delete
			return \$_return
		fi
		}

		# Return the object reference.
		if [ -n \"\$_var\" ]; then
			setvar \"\$_var\" \$this
		else
			echo \$this
		fi
		return 0
	}"

	# Create destructor.
	eval "$class.delete() {
		${clean:+
		$clean \"\$@\" || return
		# Unregister cleanup function from EXIT trap
		local nl
		nl='$IFS'
		bsda_obj_freeOnExit=\"\${bsda_obj_freeOnExit%%\$this*\}\${bsda_obj_freeOnExit#*\$this\$nl\}\"
		}

		${aggregations:+eval \"$(
		for alias in $aggregations; do
			echo \\\$\${this}$alias.delete
		done
		)\"}

		# Delete methods and attributes.
		$bsda_obj_namespace:deleteMethods \$this \"$methods\"
		$bsda_obj_namespace:deleteAttributes \$this \"$attributes\"
	}"

	# Create copy method.
	eval "$class.copy() {
		local bsda_obj_doCopy reference

		bsda_obj_doCopy=1

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
		${attributes:+eval \"$(
		for attribute in $attributes; do
			echo "\${reference}$attribute=\\\"\\\$\${this}$attribute\\\""
		done
		)\"}

		${aggregations:+eval \"$(
		for alias in $aggregations; do
			echo "\\\$\${this}$alias.copy \${reference}$alias"
		done
		)\"}

	}"

	# A serialise method.
	eval "$class.serialise() {
		local serialised svar

		serialised=
		${attributes:+$(
		for attribute in $attributes; do
			echo "bsda:obj:serialiseVar svar \"\${this}$attribute\""
			echo "serialised=\"\${serialised:+\$serialised;}\$svar\""
		done
		)}
		serialised=\"\$serialised;$class.deserialise \$this\"

		${aggregations:+$(
		for alias in $aggregations; do
			echo eval \"\\\$\${this}$alias.serialise svar\"
			echo 'serialised="$svar;$serialised"'
		done
		)}

		\$caller.setvar \"\$1\" \"\$serialised\"
	}"

	# A static deserialise method.
	eval "$class.deserialise() {
		# Create method instances.
		$bsda_obj_namespace:createMethods $class $classPrefix \$1 \"$methods\"
	}"

	# A static type checker.
	eval "$class.isInstance() {
		case \"\$1\" in
		$instancePattern)
			return 0
		;;
		esac
		return 1
	}"

	# Return whether this is a class.
	eval "$class.isClass() {
		return 0
	}"

	# A static method that returns the attributes of a class.
	eval "$class.getAttributes() {
		if [ -n \"\$1\" ]; then
			setvar \"\$1\" '$attributes'
		else
			echo '$attributes'
		fi
	}"

	# A static method that returns the methods of a class.
	eval "$class.getMethods() {
		if [ -n \"\$1\" ]; then
			setvar \"\$1\" '$methods'
		else
			echo '$methods'
		fi
	}"

	# A static method that returns the class prefix.
	eval "$class.getPrefix() {
		if [ -n \"\$1\" ]; then
			setvar \"\$1\" '$classPrefix'
		else
			echo '$classPrefix'
		fi
	}"

	# A static method that returns the name of the init method.
	eval "$class.getInit() {
		if [ -n \"\$1\" ]; then
			setvar \"\$1\" '$init'
		else
			echo '$init'
		fi
	}"

	# A static method that returns the name of the cleanup method.
	eval "$class.getClean() {
		if [ -n \"\$1\" ]; then
			setvar \"\$1\" '$clean'
		else
			echo '$clean'
		fi
	}"
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
bsda:obj:createMethods() {
	local method scope
	for method in $4; do
		scope=${method%:*}
		# Get scope check from class.
		eval "scope=\"\$$2$scope\""
		# Add method name to scope.
		eval "scope=\"$scope\""
		method=${method##*:}
		eval "$3.$method() {
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
		}"
	done
}

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

	# Delete the given object when returning to the caller.
	$caller.delete() {
		delete_${caller}=\"\$1.delete;\${delete_${caller}}\"
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
# @param delete_${caller}
#	The list of objects to delete when returning to the caller.
# @param setvars_${caller}
#	The list of variables to copy into the caller context.
# @param bsda_obj_callStackCount
#	Is decremented by 1.
#
bsda:obj:callerFinish() {
	# Delete objects
	eval eval "\${delete_${caller}}"
	unset delete_${caller}

	# Remove the bsda:obj:callerSetvar() wrapper.
	unset -f $caller.setvar $caller.delete \
	         $caller.getObject $caller.getClass
	# Decrement the call stack counter.
	bsda_obj_callStackCount=$(($bsda_obj_callStackCount - 1))

	# Copy variables to the caller context.
	local _var IFS
	IFS=' '
	eval "_var=\"\$setvars_${caller}\""
	for _var in $_var; do
		# Copy variable.
		eval "setvar $_var \"\$$caller$_var\""
		# Delete variable from stack.
		unset $caller$_var
	done
	# Delete list of variables from stack.
	unset setvars_${caller}
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
# @param setvars_${caller}
#	A list of all the stored variables for the caller context.
#
bsda:obj:callerSetvar() {
	# Print if no return variable was specified.
	test -z "$1" && echo "$2" && return

	# Store value.
	setvar $caller$1 "$2"
	# Register variable.
	eval "setvars_${caller}=\$setvars_${caller}\${setvars_${caller}:+ }$1"
}

#
# Serialises a single variable by a given name.
#
# @param 1
#	The name of the variable to return the string to.
# @param 2
#	The name of the variable to serialise.
#
bsda:obj:serialiseVar() {
	if [ -n "$1" ]; then
		setvar "$1" "$2=\"\$(printf '$(eval "echo \"\$$2\"" | bsda:obj:escape)')\""
	else
		echo "$2=\"\$(printf '$(eval "echo \"\$$2\"" | bsda:obj:escape)')\""
	fi
}

#
# Escapes strings on stdin for serialisation.
#
# The printf command can be used for deserialisation.
#
bsda:obj:escape() {
	/usr/bin/vis -woe"'%\$\"-"
}

#
# Install traps for garbage collection upon termination of the process.
#
bsda:obj:trap() {
	trap bsda:obj:exit EXIT
	trap "trap - HUP INT TERM;exit 1" HUP INT TERM
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
# Objects spawning processes are responsible for killing them in their
# destructor.
#
# @param bsda_obj_freeOnExit
#	The list of objects to call
#
bsda:obj:exit() {
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
	# Wait if any children stick around.
	wait
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
# Ignore nullptr copy.
#
.copy() {
	:
}

#
# Ignore nullptr serialise.
#
.serialise() {
	:
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

# Setup getvar for symmetry with setvar
if ! getvar 2> /dev/null; then
	#
	# Returns a variable from a given reference.
	#
	# The variable is either written to a named variable, or in
	# absence of one, output to stdout.
	#
	# @param 1
	#	If this is the sole parameter it is a reference to
	#	the variable to output to stdout. If a second parameter
	#	exists, it is the name of the variable to write to.
	# @param 2
	#	The reference to the variable to return.
	#
	getvar() {
		if [ -n "$2" ]; then
			eval "$1=\"\$$2\""
		else
			eval "echo \"\$$1\""
		fi
	}
fi
