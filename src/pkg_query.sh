test -n "$_pkg_query_" && return 0
readonly _pkg_query_=1

#
# Provides wrappers around pkg-query(8).
#

#
# Return info for the given packages.
#
# @param 1
#	The format string
# @param @
#	The packages to select
#
pkg:query:select() {
	/usr/sbin/pkg query "$@"
}

#
# List all leaves.
#
# @param 1
#	The format string
#
pkg:query:leaves() {
	/usr/sbin/pkg query -e '%?r=0' "$1"
}

#
# List all autoremove packages.
#
# @param 1
#	The format string
#
pkg:query:auto() {
	/usr/sbin/pkg query -e '%a=1' "$1"
}

#
# List dependencies of the given packages.
#
# @param 1
#	The format string
# @param @
#	The packages to get dependencies of
#
pkg:query:depends() {
	local fmt
	fmt="$(echo "$1" | /usr/bin/sed 's/%/%d/g')"
	shift
	/usr/sbin/pkg query "$fmt" "$@" | /usr/bin/sort -u
}

#
# List all packages which are required only by the given packages.
#
# @param 1
#	The format string for input and output
# @param @
#	The pacakges to filter by.
#
pkg:query:required_only_by() {
	local fmt depends pkg
	fmt="$1"
	shift
	awk -vFMT="$fmt" '
	BEGIN {
		QUERY = "/usr/sbin/pkg query"
		DFMT = FMT
		gsub(/%/, "%d", DFMT)
		RFMT = FMT
		gsub(/%/, "%r", RFMT)

		# Get all the packages to check
		delete aleaves
		leaves = ""
		for (i = 1; i < ARGC; ++i) {
			if (!(ARGV[i] in aleaves)) {
				aleaves[ARGV[i]]
				leaves = leaves " " ARGV[i]
			}
			delete ARGV[i]
		}

		# Get all the dependencies of leaves
		delete adepends
		depends = ""
		cmd = QUERY " \"" DFMT "\" " leaves
		while (0 < (cmd | getline)) {
			if (!($0 in adepends)) {
				adepends[$0]
				depends = depends " " $0
			}
		}
		close(cmd)

		# Get all the dependencies required only by leaves
		depend = ""
		required_by_others = 1
		cmd = QUERY " \"" FMT " " RFMT "\" " depends
		while (0 < (cmd | getline)) {
			if (depend != $1) {
				if (!required_by_others) {
					print depend
				}
				required_by_others = 0
				depend = $1
			}
			if (!($2 in aleaves)) {
				required_by_others = 1
			}
		}
		close(cmd)
		if (!required_by_others) {
			print depend
		}
	}' "$@" | /usr/bin/sort -u
}
