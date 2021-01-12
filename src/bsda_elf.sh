test -n "$_bsda_elf_" && return 0
readonly _bsda_elf_=1

. ${bsda_dir:-.}/bsda_err.sh

#
# The bsda:elf package provides access to the symbols of ELF executable
# files.
#

#
# Error/exit codes for error reporting.
#
# | Code             | Severity | Meaning                    |
# |------------------|----------|----------------------------|
# | E_BSDA_ELF_NOENT | error    | Cannot read the given file |
#
bsda:err:createECs E_BSDA_ELF_NOENT

#
# Grants access to the symbol values in a binary file.
#
bsda:obj:createClass bsda:elf:File \
	r:private:filename "The name of the file" \
	r:private:virtual  "The virtual address offset" \
	r:private:symbols  "A list of all symbols with address and size" \
	i:private:init     "Initialise the list of symbols" \
	x:private:getTuple "Retrieve parameters of a single symbol" \
	x:public:fetchEnc  "Fetch an encoded value of a symbol" \
	x:public:fetch     "Fetch a printable string symbol value"

#
# Initialise symbol list for a given file.
#
# Determines the virtual address offset and creates a list of symbols.
#
# @param 1
#	The file name to read symbols from
# @retval 0
#	Reading the file succeeded
# @retval 1
#	An error occurred
# @throws E_BSDA_ELF_NOENT
#	Cannot read the given file
#
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

#
# Retrieve the type, address and size of a symbol value.
#
# The _OUTPUT FORMAT_ section of nm(1) documents the symbol types.
#
# @param &1
#	Symbol type destination variable
# @param &2
#	Absolute symbol address destination variable
# @param &3
#	Symbol size destination variable
# @param 4
#	The name of the symbol to access
#
bsda:elf:File.getTuple() {
	local name type addr size offset
	eval "$($this.getSymbols | /usr/bin/grep -F "name='${4}'")"
	$this.getVirtual offset
	$caller.setvar "${1}" "${type}"
	$caller.setvar "${2}" "$((addr - offset))"
	$caller.setvar "${3}" "$((size))"
}

#
# Extracts a symbol from the binary and runs it through an encoder.
#
# | Tag | Encoder      | Description                      |
# |-----|--------------|----------------------------------|
# | vis | vis(1)       | Escapes non-printable characters |
# | b64 | b64encode(1) | Base64 encoder                   |
# | uue | uuencode(1)  | Binary file encoder              |
# | hex | hexdump(1)   | Formattable hex and octal output |
#
# @param &1
#	Destination variable for the encoded value
# @param 2
#	The symbol name to fetch
# @param 3
#	The encoder tag
# @param @
#	Remaining arguments are forwarded to the encoder
#
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

#
# Extracts a printable string value from the binary.
#
# @param &1
#	Destination variable for the encoded value
# @param 2
#	The symbol name to fetch
#
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
