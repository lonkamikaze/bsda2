test -n "$_bsda_elf_" && return 0
readonly _bsda_elf_=1

. ${bsda_dir:-.}/bsda_err.sh

bsda:err:createECs E_BSDA_ELF_NOENT

bsda:obj:createClass bsda:elf:File \
	r:private:filename \
	r:private:symbols \
	i:private:init \
	x:public:fetchEnc \
	x:public:fetch \
	x:public:select \

bsda:elf:File.init() {
	if ! [ -r "$1" ]; then
		bsda:err:raise E_BSDA_ELF_NOENT "ERROR: File not found: ${1}"
		return 1
	fi
	local virtual
	setvar ${this}filename "$1"
	setvar virtual "$(
		/usr/bin/readelf -Wl "$1" 2>&- | while read -r type offs virt tail; do
			if [ "${type}" = "LOAD" ] && [ $((offs)) -eq 0 ]; then
				echo "${virt}"
				return
			fi
		done
	)"
	setvar ${this}symbols "$(
		addr=x
		/usr/bin/nm --demangle --print-size "$1" 2>&- \
		| while read -r addr size type name; do
			if [ -n "${name}" ]; then
				echo "name='${name}';type=${type};addr=$((0x${addr} - virtual));size=$((0x${size}));"
			fi
		done
	)"
}

bsda:elf:File.fetchEnc() {
	local dst sym mode value filename addr name type addr size
	dst="$1"
	sym="$2"
	mode="$3"
	shift;shift;shift
	value=
	addr="$($this.getSymbols | /usr/bin/grep -F "name='${sym}';")"
	if [ -n "${addr}" ]; then
		eval "${addr}"
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
	local value filename addr name type addr size
	value=
	addr="$($this.getSymbols | /usr/bin/grep -F "name='${2}';")"
	if [ -n "${addr}" ]; then
		eval "${addr}"
		$this.getFilename filename
		value="$(/bin/dd if="${filename}" bs=1 skip="${addr}" count="${size}" conv=sparse 2>&-)"
	fi
	$caller.setvar "${1}" "${value}"
}
