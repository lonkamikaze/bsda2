#!/usr/bin/awk -f
#
# Convert pkg_checksum.c version 2 checksums in input column 2 from
# z-base-32 encoding to hex encoding to allow comparisons with the
# blake2 hashes produced by b2sum(1).
# Discard unmatching input lines.
#
# Implementation Details
# ----------------------
#
# The z-base-32 encoding is described in this document:
# https://philzimmermann.com/docs/human-oriented-base-32-encoding.txt
#
# Unfortunately pkg_checksum.c contains a proprietary implementation
# that contains a bug. The z-base-32 stream it produces decodes into
# the following:
#
# byte index:        0|       1|       2|       3|       4
# bit index:  76543210|76543210|76543210|76543210|76543210
#
# z-base-32 stream index:      0|    1|    2|    3|    4|    5|    6|    7
# decoded byte index:      00000|11000|11111|22221|32222|33333|44433|44444
# decoded bit index:       43210|10765|65432|32107|07654|54321|21076|76543
#
# The original bytes can be restored by reversing the order of the z-base-32
# digits:
#
# z-base-32 stream index:      7|    6|    5|    4|    3|    2|    1|    0
# decoded byte index:      44444|44433|33333|32222|22221|11111|11000|00000
# decoded bit index:       76543|21076|54321|07654|32107|65432|10765|43210
#
# Now every byte contains the right bits in the right order, however the
# byte order is reversed. This is worked around by producing bytwise hex
# output from back to front.
#

#
# Setup z-base-32 -> bit and bit -> hex tables.
#
BEGIN {
	# use the input separator as output separator
	OFS = FS

	# z-base-32 chars: ybndrfg8ejkmcpqxot1uwisza345h769
	CHARVS["y"] = CHARVS["Y"] = "00000"
	CHARVS["b"] = CHARVS["B"] = "00001"
	CHARVS["n"] = CHARVS["N"] = "00010"
	CHARVS["d"] = CHARVS["D"] = "00011"
	CHARVS["r"] = CHARVS["R"] = "00100"
	CHARVS["f"] = CHARVS["F"] = "00101"
	CHARVS["g"] = CHARVS["G"] = "00110"
	CHARVS["8"]               = "00111"
	CHARVS["e"] = CHARVS["E"] = "01000"
	CHARVS["j"] = CHARVS["J"] = "01001"
	CHARVS["k"] = CHARVS["K"] = "01010"
	CHARVS["m"] = CHARVS["M"] = "01011"
	CHARVS["c"] = CHARVS["C"] = "01100"
	CHARVS["p"] = CHARVS["P"] = "01101"
	CHARVS["q"] = CHARVS["Q"] = "01110"
	CHARVS["x"] = CHARVS["X"] = "01111"
	CHARVS["o"] = CHARVS["O"] = "10000"
	CHARVS["t"] = CHARVS["T"] = "10001"
	CHARVS["1"]               = "10010"
	CHARVS["u"] = CHARVS["U"] = "10011"
	CHARVS["w"] = CHARVS["W"] = "10100"
	CHARVS["i"] = CHARVS["I"] = "10101"
	CHARVS["s"] = CHARVS["S"] = "10110"
	CHARVS["z"] = CHARVS["Z"] = "10111"
	CHARVS["a"] = CHARVS["A"] = "11000"
	CHARVS["3"]               = "11001"
	CHARVS["4"]               = "11010"
	CHARVS["5"]               = "11011"
	CHARVS["h"] = CHARVS["H"] = "11100"
	CHARVS["7"]               = "11101"
	CHARVS["6"]               = "11110"
	CHARVS["9"]               = "11111"

	# hex chars
	BITSV["0000"] = "0"
	BITSV["0001"] = "1"
	BITSV["0010"] = "2"
	BITSV["0011"] = "3"
	BITSV["0100"] = "4"
	BITSV["0101"] = "5"
	BITSV["0110"] = "6"
	BITSV["0111"] = "7"
	BITSV["1000"] = "8"
	BITSV["1001"] = "9"
	BITSV["1010"] = "a"
	BITSV["1011"] = "b"
	BITSV["1100"] = "c"
	BITSV["1101"] = "d"
	BITSV["1110"] = "e"
	BITSV["1111"] = "f"
}

$2 ~ /^2\$/ {
	sub(/^2\$/, "", $2)
	n = split($2, digits, "")

	# create binary string in reverse order
	bits = ""
	for (i = 1; i <= n; ++i) {
		bits = CHARVS[digits[i]] bits
	}

	# create hex string in reverse byte order
	$2 = ""
	for (i = length(bits) % 8 + 1; i <= length(bits); i += 8) {
		$2 = BITSV[substr(bits, i, 4)] BITSV[substr(bits, i + 4, 4)] $2
	}
	$2 = "2$" $2

	print
}
