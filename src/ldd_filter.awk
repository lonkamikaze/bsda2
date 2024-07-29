#!/usr/bin/awk -f
#
# Compile a set of dynamic linker errors.
#
# Expects the output of ldd(1) on input and collects a set of errors
# and missing dpendencies for each binary given to ldd.
# The script discards irrelevant errors (such as the information
# that the given file is not an ELF executable/library).
# When necessary the binary is fed into readelf(1) to obtain more
# specific information.
#
# Each error is output as a set:
#
# 1. binary name
# 2. missing library or other info
# 3. tags, a comma separated list of tags consisting of a single
#    primary tag followed by optional secondary tags
#
# The following primary tags exist:
#
# | Tag     | Binary | Info                | Description                    |
# |---------|--------|---------------------|--------------------------------|
# | compat  | yes    | dependency path     | Path matches `*/lib*/compat/*` |
# | miss    | yes    | dependency filename | Dependency was not found       |
# | verbose | yes    | error message       | Binary specific ldd(1) error   |
# | invalid | -      | whole input line    | Unknown ldd(1) output          |
#
# The following secondary tags can be appended to primary tags with a comma
# separator:
#
# | Tag      | Description                                                     |
# |----------|-----------------------------------------------------------------|
# | direct   | The missing dependency is a direct dependency                   |
# | indirect | The missing dependency is an indirect dependency                |
# | os/abi   | The given binary is an unbranded ELF binary, i.e. OS/ABi = NONE |
#
# The direct and indirect tags are mutually exclusive.
#
# Originally the ldd(1) filter was introduced as an inline awk command
# to work around a bug in formatted ldd output:
# [see](https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=259069).
#
# Over time more and more functionality was introduced into the filter
# until it became its own entity.
#
# @param OFS
#	Set to control the tuple item separator
# @param COMPAT
#	Set to 1 to flag binaries linking compatibility libraries,
#	set to 0 otherwise
# @param VERBOSE
#	Set to 1 to output interesting information that does not
#	indicate a missing dependency
# @param FILTER
#	Set to 1 to determine secondary tags, if 0 no information
#	whether a dependency is direct or indirect or if the binary
#	is unbranded (i.e. the os/abi tag), will be produced
#

#
# Output each row only once, at least on FreeBSD
# stable/13-n247530-3637d2a1835e ldd(1) prints missing dependencies
# many times.
#
# This output filter changed the runtime for `pkg_libck samba413` after
# a libicu update from >120s to ~4s, supposedly because every reported
# missing dependency corresponds to a readelf(1) call and this package
# produces 23601 lines of output without the filter.
#
# @param bin,info,tag
#	A tuple consisting of a binary name, the issue information
#	and a set of tags
#
function printrow(bin, info, tags) {
	# print only if this binary/info combination has not been printed yet
	if (!ROW[bin, info]++) {
		print(bin, info, tags)
	}
}

#
# Call readelf on the given binary and add secondory tags.
#
# - `os/abi` for unbranded ELF binaries
# - `direct` where the given library is a direct dependency of the
#   given binary
# - `indirect` where the given library is an indirect dependency of
#   the given binary
#
# @param bin,lib,tags
#	A tuble consisting of a binary name, the missed library and
#	a tag, either miss or compat
#
function readelf_tag(bin, lib, tags, _cmd, _bin, _direct, _osabi) {
	if (FILTER && !READELF[bin, lib]++) {
		# just escape every character in the file name, this
		# should at least cover the easy stuff like whitespace
		_bin = bin
		gsub(/./, "\\\\&", _bin)
		_cmd = "/usr/bin/readelf -hd " _bin
		_direct = _osabi = 0
		while ((_cmd | getline) > 0) {
			_direct += (0 < index($0, "Shared library: [" lib "]"))
			_osabi  += (/^ *OS\/ABI: *NONE$/)
		}
		close(_cmd)
		# bail if nothing should be printed, but we must not
		# bail before calling close(_cmd)
		if (!VERBOSE && (_osabi || !_direct)) { return }
		#   ^~~~~~~~     ^~~~~~    ^~~~~~~~
		#   |            |         | bail on indirect dependency
		#   |            | bail if OS/ABI is not set (binary is not branded)
		#   | never bail when verbose

		# append tags
		tags = tags (_osabi  ? ",os/abi" : "") \
		            (_direct ? ",direct" : ",indirect")
	}
	printrow(bin, lib, tags)
}

# update binary name
/^[^\t].*:$/ {
	sub(/:$/, "")
	BIN=$0
	next
}

# compat library
COMPAT && /^\t.* => .*\/lib[^\/]*\/compat\/.* \(0x[0-9a-f]+\)$/ {
	sub(/^\t.* => /, "")
	sub(/ \(0x[0-9a-f]+\)$/, "")
	readelf_tag(BIN, $0, "compat")
	next
}

# missing library
/\(0\)$/ || /^\t.* => not found \(0x[0-9a-f]+\)$/ {
	sub(/^\t/, "")
	sub(/ => .*/, "")
	readelf_tag(BIN, $0, "miss")
	next
}

# ignore
/^\t.* \(0x[0-9a-f]+\)$/                  || # library was found
/^ldd: .*: not a dynamic ELF executable$/ || # non-executable
/^ldd: .*: not a .* ELF shared object$/   || # non-executable
/^ldd: .*: Invalid argument$/             || # non-executable
/^ldd: .*: unsupported machine$/          || # cross-platform executable
/^\[preloaded\]$/                         || # start of preloaded section
/^.*: exit status 1$/                     {  # redundant message
	next
}

# verbose error
VERBOSE && /ldd: .*: .*/ {
	sub(/ldd: /, "")
	file=$0
	sub(/: [^:]*$/, "", file)
	sub(/.*: /, "")
	printrow(file, $0, "verbose")
	next
}

# unknown/invalid ldd output
VERBOSE {
	printrow("", $0, "invalid")
}

