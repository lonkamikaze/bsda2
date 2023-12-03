# Include once.
test -n "$_bsda_container_" && return 0
readonly _bsda_container_=1

. ${bsda_dir:-.}/bsda_obj.sh
. ${bsda_dir:-.}/bsda_util.sh

#
# A package containing container classes.
#

#
# An array class.
#
# This array class supports push()/pop(), random access.
#
# @warning
#	If the array is serialised the values will be treated as data.
#	I.e. references are not followed up.
#
bsda:obj:createClass bsda:container:Array \
	i:private:init     "The constructor" \
	c:private:clean    "The destructor" \
	r:public:count     "The number of elements the array contains" \
	x:public:[         "Random access operator to read/write values" \
	x:public:push      "Push a new value to the end of the array" \
	x:public:pop       "Pop the latest value from the end of the array" \
	x:public:foreach   "Call back with every value" \
	x:public:serialise "Serialise the array" \
	x:public:copy      "Copy the array"

#
# The constructor fills the array with initial values.
#
# @param @
#	A list of values
#
bsda:container:Array.init() {
	setvar ${this}count 0
	while [ $# -gt 0 ]; do
		$this.push "$1"
		shift
	done
}

#
# The destructor wipes all values from memory.
#
bsda:container:Array.clean() {
	local i count
	$this.getCount count
	i=0
	while [ $i -lt $count ]; do
		unset ${this}_val_$i
		i=$((i + 1))
	done
}

#
# Push onto the end of the array.
#
# @param *
#	All arguments are concatenated with white space and pushed
#	as a single value
#
bsda:container:Array.push() {
	local count
	$this.getCount count
	setvar ${this}_val_$count "$*"
	setvar ${this}count $((count + 1))
}

#
# Pop the last value off the array and return it.
#
# @param &1
#	The variable to return the value to
#
bsda:container:Array.pop() {
	local count value
	$this.getCount count
	if [ $count -le 0 ]; then
		return 1;
	fi
	count=$((count - 1))
	getvar value ${this}_val_$count
	$caller.setvar "$1" "$value"
	unset ${this}_val_$count
	setvar ${this}count $count
	return 0
}

#
# Call back the given function with every key/value pair.
#
# Terminates early if the function returns a non-null value.
#
# @param 1
#	The function/command to call
# @retval 0
#	The loop went through all key/value pairs
# @retval *
#	The return value of the function call that ended the loop
#
bsda:container:Array.foreach() {
	local key count
	$this.getCount count
	key=0
	while [ $key -lt $count ]; do
		eval "$1 \"${key}\" \"\${${this}_val_$key}\"" || return $?
		key=$((key + 1))
	done
}

#
# The random access operator, allows access to every value by its key.
#
# It supports a read and a write mode.
#
#	$array.[ 2 ]= "monkey" # Assign monkey
#	$array.[ 2 ]           # Output monkey
#	$array.[ 2 ] island    # Assign monkey to island
#
# @param 1
#	The array key (index) to access
# @param 2
#	Should be ] to read or ]= to write
# @param 3
#	The value to assign for write access
# @param &3
#	The variable to assign the value to
# @retval 0
#	Operation completed
# @retval 1
#	Read access attempt out of bounds
# @retval 2
#	No valid read/write operator present
#
bsda:container:Array.[() {
	local i count
	$this.getCount count
	i=$(($1))
	case "$2" in
	"]=")
		shift 2
		setvar ${this}_val_$i "$*"
		if [ $i -ge $count ]; then
			setvar ${this}count $((i + 1))
		fi
		;;
	"]")
		if [ $i -ge $count ]; then
			return 1
		fi
		local value
		getvar value ${this}_val_$i
		$caller.setvar "$3" "${value}"
		;;
	*)
		return 2
	esac
	return 0
}

#
# Clears out array items that would not be overwritten by the coming
# seserialisation.
#
# @param 1
#	The object ID of the array about to be deserialised
# @param 2
#	The length of the array about to be deserialised
#
bsda:container:Array.serialise_clear() {
	local i
	i=$2
	while [ $i -lt $((${1}count)) ]; do
		unset ${1}_val_$i
		i=$((i + 1))
	done
}

#
# Serialise the array.
#
# @parma &1
#	The variable to write the serialised instance to
#
bsda:container:Array.serialise() {
	local i count serialised svar
	$this.getCount count
	serialised="$class.serialise_clear $this $((count));${this}count=$((count))"
	i=0
	while [ $i -lt $count ]; do
		bsda:obj:serialiseVar svar ${this}_val_$i
		serialised="$serialised;$svar"
		i=$((i + 1))
	done
	serialised="$serialised;$class.deserialise $this"
	$caller.setvar "$1" "$serialised"
}

#
# Lambda function for bsda:container:Array.copy().
#
bsda:container:Array.copy_lambda() {
	$array.push "$2"
}

#
# Copy the array.
#
# @parma &1
#	The variable to receive the new array reference
#
bsda:container:Array.copy() {
	local array
	$class array
	$this.foreach $class.copy_lambda
	$caller.setvar "$1" "$array"
}

#
# A key/value storage class.
#
bsda:obj:createClass bsda:container:Map \
	i:private:init     "The constructor" \
	c:private:clean    "The destructor" \
	r:private:keys     "A list of key hashes" \
	r:private:addCount "The number of keys added since last compression" \
	r:private:rmKeys   "The keys removed since last compression" \
	r:private:rmCount  "The number of keys removed since compression" \
	x:public:[         "Random access operator" \
	x:public:foreach   "Callback with a key/value pair" \
	x:public:getCount  "Returns the number of stored key/value pairs" \
	x:public:serialise "Serialise the map" \
	x:public:copy      "Copy the map"

#
# A helper function to roll out cached activities.
#
bsda:container:Map.compress() {
	local IFS keys
	log .set_ifs
	if [ $((${this}rmCount)) -gt 0 ]; then
		local rmkeys
		$this.getRmKeys rmkeys
		$this.getKeys keys
		log ${this}keys= "$(echo "$keys" | /usr/bin/grep -vFx "$rmkeys")"
		setvar ${this}rmKeys
		setvar ${this}rmCount 0
	fi
	if [ $((${this}addCount)) -gt 0 ]; then
		$this.getKeys keys
		log ${this}keys= "$(echo "${keys}" | /usr/bin/awk '!a[$0]++')"
		setvar ${this}addCount 0
	fi
}

#
# The constructor adds initial key/value pairs to the map.
#
# @param 1
#	The first key
# @param 2
#	The first value
# @param @
#	More key/value pairs
#
bsda:container:Map.init() {
	setvar ${this}keys
	setvar ${this}addCount 0
	setvar ${this}rmKeys
	setvar ${this}rmCount 0
	while [ $# -gt 0 ]; do
		$this.[ "$1" ]= "$2"
		shift 2
	done
}

#
# The destructor clears the key/value storage.
#
bsda:container:Map.clean() {
	local IFS key
	IFS=$'\n'
	for key in $($this.getKeys); do
		unset ${this}_val_$key
		unset ${this}_key_$key
	done
}

#
# A helper function that adds a new key to the storage.
#
# @param 1
#	The key to add
#
bsda:container:Map.addKey() {
	if [ $((${this}rmCount)) -gt 0 ]; then
		$class.compress
	fi
	log ${this}keys.push_back "$1"
	if [ $((${this}addCount += 1)) -ge 1024 ]; then
		$class.compress
	fi
}

#
# A helper function that removes a key from the storage.
#
# @param 1
#	The key to remove
#
bsda:container:Map.rmKey() {
	log ${this}rmKeys.push_back "$1"
	if [ $((${this}rmCount += 1)) -ge 1024 ]; then
		$class.compress
	fi
}

#
# The random access operator, allows access to every value by its key.
#
# It supports a read, delete and a write mode.
#
#	$map.[ monkey ]= "island" # Assign monkey => island
#	$map.[ monkey ]           # Output island
#	$map.[ monkey ] dance     # Assign island to dance
#	$map.[ monkey ]x          # Delete monkey => island
#
# @param 1
#	The key to access
# @param 2
#	Should be ] to read, ]= to write and ]x to delete
# @param 3
#	The value to assign for write access
# @param &3
#	The variable to assign the value to
# @retval 0
#	Operation completed
# @retval 2
#	No valid read/write operator present
#
bsda:container:Map.[() {
	local key
	key=$(/sbin/sha256 -qs "$1")
	case "$2" in
	"]=")
		$class.addKey $key
		setvar ${this}_key_$key "$1"
		shift 2
		setvar ${this}_val_$key "$*"
		;;
	"]x")
		unset ${this}_key_$key
		unset ${this}_val_$key
		$class.rmKey $key
		;;
	"]")
		local value
		getvar value ${this}_val_$key
		$caller.setvar "$3" "$value"
		;;
	*)
		return 2
	esac
	return 0
}

#
# Call back the given function with every key/value pair.
#
# Terminates early if the function returns a non-null value.
#
# @param 1
#	The function/command to call
# @retval 0
#	The loop went through all key/value pairs
# @retval *
#	The return value of the function call that ended the loop
#
bsda:container:Map.foreach() {
	$class.compress
	local IFS key keys
	$this.getKeys keys
	log keys.set_ifs
	for key in $keys; do
		eval "$1 \"\${${this}_key_$key}\" \"\${${this}_val_$key}\"" \
		|| return $?
	done
}

#
# Returns the number of key/value pairs stored in the map.
#
# @param &1
#	The variable to store the number to
#
bsda:container:Map.getCount() {
	$class.compress
	local count
	log ${this}keys.count count
	$caller.setvar "$1" "$count"
}

#
# Try to clear map before it is overwritten by serialisation.
#
# This prevents leaking stale data.
#
# @param 1
#	The object ID of the map about to be deserialised
#
bsda:container:Map.serialise_clear() {
	class=bsda:container:Map $1.clean 2>&- ||:
}

#
# Serialise the map.
#
# @parma &1
#	The variable to write the serialised instance to
#
bsda:container:Map.serialise() {
	$class.compress
	local IFS key keys serialised keyvar valvar
	$this.getKeys keys
	log keys.set_ifs
	bsda:obj:serialiseVar serialised ${this}keys
	serialised="$class.serialise_clear $this;$serialised;${this}addCount=0;${this}rmKeys=;${this}rmCount=0"
	for key in $keys; do
		bsda:obj:serialiseVar keyvar ${this}_key_$key
		bsda:obj:serialiseVar valvar ${this}_val_$key
		serialised="$serialised;$keyvar;$valvar"
	done
	serialised="$serialised;$class.deserialise $this"
	$caller.setvar "$1" "$serialised"
}

#
# Lambda function for bsda:container:Map.copy().
#
bsda:container:Map.copy_lambda() {
	$map.[ "$1" ]= "$2"
}

#
# Copy the map.
#
# @parma &1
#	The variable to receive the new map reference
#
bsda:container:Map.copy() {
	local map
	$class map
	$this.foreach $class.copy_lambda
	$caller.setvar "$1" "$map"
}
