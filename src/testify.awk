#!/usr/bin/awk -f
#
# Append "|| bsda:test:err …" to every command in a shell script.
#

BEGIN {
	# Define states
	ST_REG = 0    # Regular state
	ST_SQUOT = 1  # Inside single quotes
	ST_DQUOT = 2  # Inside double quotes
	ST_DSQUOT = 3 # Inside dollar single quotes

	TOP = 0
	STATE[TOP] = ST_REG
}

#
# Manage single and double quotes.
#
# This maintains a state stack, representing the nesting of states.
#
# The current line is parsed character by character, the characters
# are interpreted according to the top of the state stack. Depending
# on the characters encountered a new state is pushed on top of the
# stack or the top is pointed back down to the previous state.
#
# If by the end of the line the stack top is not at the bottom the
# line is printed as is and the next line is pulled in to finish
# parsing.
#
{
	do {
		for (i = 1; i <= length; ++i) {
			ch = substr($0, i, 1)
			# Single quotes are simple
			if (STATE[TOP] == ST_SQUOT) {
				if (ch == "'") {
					--TOP
				}
				continue
			}
			# All the following states support \ escapes
			if (ch == "\\") {
				++i
				continue
			}
			# Double quotes
			if (STATE[TOP] == ST_DQUOT) {
				if (ch == "\"") {
					--TOP
				} else if (ch == "$") {
					# Peek ahead
					ch = substr($0, i, 2)
					if (ch == "$(") {
						++i
						STATE[++TOP] = ST_REG
					}
					if (ch == "$'") {
						++i
						STATE[++TOP] = ST_DSQUOT
					}
				}
				continue
			}
			# Dollar single quotes
			if (STATE[TOP] == ST_DSQUOT) {
				if (ch == "'") {
					--TOP
				}
				continue
			}
			# Regular state, or command substitution
			if (ch == "'") {
				STATE[++TOP] = ST_SQUOT
			} else if (ch == "\"") {
				STATE[++TOP] = ST_DQUOT
			} else if (ch == "$") {
				# Peek ahead
				ch = substr($0, i, 2)
				if (ch == "$'") {
					++i
					STATE[++TOP] = ST_DSQUOT
				}
			} else if (ch == "(") {
				STATE[++TOP] = ST_REG
			} else if (ch == ")") {
				--TOP
			}
		}
		# About to get the next line, print this one
		if (STATE[TOP] != ST_REG) {
			print
		}
	} while (STATE[TOP] != ST_REG && getline > 0)
}

# Do not append error checks to lines not ending in a command.
/((^|then|else|do|in|[({&;])|[ \t]*\\)$/ {
	print
	next
}

# Append the error check.
{
	print $0 " || bsda:test:err \"" FILENAME "\" $LINENO $?"
}
