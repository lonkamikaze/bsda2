#!/usr/bin/awk -f
#
# Transplant special keywords from one plist to the next, seeking
# to put them into the same context.
#
# @param ARGV[1]
#	The new plist file name
# @param ARGV[2]
#	The old plist file name
#

BEGIN {
	# List of auto-prefixes
	AUTO["@sample "]
}

# Index the new plist file
NR == FNR {
	PLIST[NR] = $0
	PLIST_IND[$0] = NR
	PLIST_CNT = NR
	next
}

# Index the old plist file
{
	OLD_PLIST[NR - PLIST_CNT] = $0
	OLD_PLIST_CNT = NR - PLIST_CNT
	# Strip auto-prefixes from the new plist if the file
	# is listed but does not have the prefix.
	for (auto in AUTO) {
		if (auto $0 in PLIST_IND) {
			PLIST[PLIST_IND[auto $0]] = $0
		}
	}
}

# Print plist
END {
	PLIST_PRINT = 1
	# Find keyword in old plist
	for (NR = 1; NR <= OLD_PLIST_CNT; ++NR) {
		# Accumulate files that come before the next
		# keyword.
		PREVIOUS[OLD_PLIST[NR]]

		# Check for keyword
		if (OLD_PLIST[NR] ~ /(^|%%)@[[:alnum:]]+ /) {
			# Skip if already in new plist
			if (OLD_PLIST[NR] in PLIST_IND) {
				continue
			}
			# Read the new plist file from the
			# back until a line from the PREVIOUS
			# list is encountered.
			for (i = PLIST_CNT; i >= PLIST_PRINT; --i) {
				if (PLIST[i] in PREVIOUS) {
					break
				}
			}
			# Print everything before and including
			# the match.
			for (; PLIST_PRINT <= i; ++PLIST_PRINT) {
				print PLIST[PLIST_PRINT]
			}
			# Print the current (keyword) line
			print OLD_PLIST[NR]
		}
	}

	# Print remaining plist
	for (; PLIST_PRINT <= PLIST_CNT; ++PLIST_PRINT) {
		print PLIST[PLIST_PRINT]
	}
}
