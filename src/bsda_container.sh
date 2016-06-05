# Include once.
test -n "$_bsda_container_" && return 0
readonly _bsda_container_=1

. ${bsda_dir:-.}/bsda_obj.sh

# Not serialisable!

bsda:obj:createClass bsda:container:Array \
	i:private:init \
	c:private:clean \
	r:public:count \
	x:public:[ \
	x:public:push \
	x:public:pop \
	x:public:foreach

bsda:container:Array.init() {
	setvar ${this}count 0
	while [ $# -gt 0 ]; do
		$this.push "$1"
		shift
	done
}

bsda:container:Array.clean() {
	local i count
	$this.getCount count
	i=0
	while [ $i -lt $count ]; do
		unset ${this}_val_$i
		i=$((i + 1))
	done
}

bsda:container:Array.push() {
	local count
	$this.getCount count
	setvar ${this}_val_$count "$*"
	setvar ${this}count $((count + 1))
}

bsda:container:Array.pop() {
	local count value
	$this.getCount count
	if [ $count -le 0 ]; then
		return 1;
	fi
	count=$((count - 1))
	bsda:obj:getVar value ${this}_val_$count
	$caller.setvar "$1" "$value"
	unset ${this}_val_$count
	setvar ${this}count $count
	return 0
}

bsda:container:Array.foreach() {
	local key count
	$this.getCount count
	key=0
	while [ $key -lt $count ]; do
		eval "$1 \"${key}\" \"\${${this}_val_$key}\""
		key=$((key + 1))
	done
}

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
		bsda:obj:getVar value ${this}_val_$i
		$caller.setvar "$3" "${value}"
		;;
	*)
		return 2
	esac
	return 0
}

bsda:container:Array.serialise() {
	local i count serialised svar
	$this.getCount count
	serialised="${this}count=$((count))"
	i=0
	while [ $i -lt $count ]; do
		bsda:obj:serialiseVar svar ${this}_val_$i
		serialised="$serialised;$svar"
		i=$((i + 1))
	done
	serialised="$serialised;$class.deserialise $this"
	$caller.setvar "$1" "$serialised"
}

bsda:container:Array.serialiseDeep() {
	bsda:container:Array.serialise "$@"
}

bsda:obj:createClass bsda:container:Map \
	i:private:init \
	c:private:clean \
	r:private:keys \
	r:private:addCount \
	r:private:rmKeys \
	r:private:rmCount \
	x:public:[ \
	x:public:foreach \
	x:public:getCount

bsda:container:Map.compress() {
	local keys count
	$this.getRmCount count
	if [ $((count)) -gt 0 ]; then
		local rmkeys
		$this.getRmKeys rmkeys
		$this.getKeys keys
		setvar ${this}keys "$(echo "$keys" | /usr/bin/grep -vFx "$rmkeys")"
		setvar ${this}rmKeys
		setvar ${this}rmCount 0
	fi
	$this.getAddCount count
	if [ $((count)) -gt 0 ]; then
		$this.getKeys keys
		setvar ${this}keys "$(echo "${keys}" | /usr/bin/sort -u)"
		setvar ${this}addCount 0
	fi
}

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

bsda:container:Map.clean() {
	local key
	for key in $($this.getKeys); do
		unset ${this}_val_$key
		unset ${this}_key_$key
	done
}

bsda:container:Map.addKey() {
	local keys count NL
	NL='
'
	$this.getRmCount count
	if [ $((count)) -gt 0 ]; then
		$class.compress
	fi
	$this.getKeys keys
	$this.getAddCount count
	setvar ${this}keys "${keys}${keys:+${NL}}$1"
	setvar ${this}addCount $((count + 1))
	if [ $((count)) -ge 1024 ]; then
		$class.compress
	fi
}

bsda:container:Map.rmKey() {
	local keys count NL
	NL='
'
	$this.getRmKeys keys
	$this.getRmCount count
	setvar ${this}rmKeys "${keys}${keys:+$NL}$1"
	setvar ${this}rmCount $((count + 1))
	if [ $((count)) -ge 1024 ]; then
		$class.compress
	fi
}

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
		bsda:obj:getVar value ${this}_val_$key
		$caller.setvar "$3" "$value"
		;;
	*)
		return 2
	esac
	return 0
}

bsda:container:Map.foreach() {
	$class.compress
	local key keys
	$this.getKeys keys
	for key in $keys; do
		eval "$1 \"\${${this}_key_$key}\" \"\${${this}_val_$key}\""
	done
}

bsda:container:Map.argCount() {
	echo $#
}

bsda:container:Map.getCount() {
	$class.compress
	local keys
	$this.getKeys keys
	$caller.setvar "$1" "$($class.argCount ${keys})"
}

bsda:container:Map.serialise() {
	$class.compress
	local key keys serialised keyvar valvar
	$this.getKeys keys
	bsda:obj:serialiseVar serialised ${this}keys
	serialised="$serialised;${this}addCount=0;${this}rmKeys=;${this}rmCount=0"
	for key in $keys; do
		bsda:obj:serialiseVar keyvar ${this}_key_$key
		bsda:obj:serialiseVar valvar ${this}_val_$key
		serialised="$serialised;$keyvar;$valvar"
	done
	serialised="$serialised;$class.deserialise $this"
	$caller.setvar "$1" "$serialised"
}

bsda:container:Map.serialiseDeep() {
	bsda:container:Map.serialise "$@"
}

