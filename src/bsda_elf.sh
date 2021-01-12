test -n "$_bsda_elf_" && return 0
readonly _bsda_elf_=1

. ${bsda_dir:-.}/bsda_err.sh

bsda:err:createECs E_BSDA_ELF_NOENT

bsda:obj:createClass bsda:elf:File \
	r:private:filename \
	r:private:virtual \
	r:private:symbols \
	i:private:init \
	x:private:getTuple \
	x:public:fetchEnc \
	x:public:fetch

bsda:elf:File.init() {
	if ! [ -r "$1" ]; then
		bsda:err:raise E_BSDA_ELF_NOENT "ERROR: Cannot read file: ${1}"
		return 1
	fi
	setvar ${this}filename "$1"
	setvar ${this}virtual "$(
		/usr/bin/readelf -Wl "$1" 2>&- | while read -r type offs virt tail; do
			if [ "${type}" = "LOAD" ] && [ $((offs)) -eq 0 ]; then
				echo "${virt}"
				return
			fi
		done
	)"
	setvar ${this}symbols "$(
		/usr/bin/nm --demangle --print-size "$1" 2>&- \
		| /usr/bin/awk "
			\$4{
				sub(/^/, \"addr=0x\")
				sub(/ /, \";size=0x\")
				sub(/ /, \";type=\")
				sub(/ /, \";name='\")
				sub(/$/, \"'\")
				print
			}
		"
	)"
}

bsda:elf:File.getTuple() {
	local name type addr size offset
	eval "$($this.getSymbols | /usr/bin/grep -F "name='${4}'")"
	$this.getVirtual offset
	$caller.setvar "${1}" "${type}"
	$caller.setvar "${2}" "$((addr - offset))"
	$caller.setvar "${3}" "$((size))"
}

bsda:elf:File.fetchEnc() {
	local dst sym mode value type addr size filename
	dst="$1"
	sym="$2"
	mode="$3"
	shift;shift;shift
	value=
	$this.getTuple type addr size "${sym}"
	if [ -n "${addr}" ]; then
		$this.getFilename filename
		value="$(
			/bin/dd if="${filename}" bs=1 skip="${addr}" count="${size}" 2>&- \
			| case "${mode}" in
			vis) /usr/bin/vis "$@";;
			b64) /usr/bin/b64encode "$@" -;;
			uue) /usr/bin/uuencode "$@" -;;
			hex) /usr/bin/hexdump "$@";;
			esac
		)"
	fi
	$caller.setvar "${dst}" "${value}"
}

bsda:elf:File.fetch() {
	local value type addr size filename
	value=
	$this.getTuple type addr size "${2}"
	if [ -n "${addr}" ]; then
		$this.getFilename filename
		value="$(/bin/dd if="${filename}" bs=1 skip="${addr}" count="${size}" conv=sparse 2>&-)"
	fi
	$caller.setvar "${1}" "${value}"
}
