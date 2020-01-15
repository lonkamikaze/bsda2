#!/usr/bin/awk -f
#
# Append "|| bsda:test:err …" to every command in a shell script.
#

BEGIN {
	# Define states
	ST_REG = 0      # Regular state
	ST_SQUOT = 1    # Inside single quotes
	ST_DQUOT = 2    # Inside double quotes
	ST_DSQUOT = 3   # Inside dollar single quotes
	ST_CASE_BLK = 4 # Inside case/esac
	ST_CASE_REG = 5 # Inside case match

	TOP = 0
	STATE[TOP] = ST_REG
	REG_STATES[ST_REG]
	REG_STATES[ST_CASE_REG]
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
			front = substr($0, i)
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
			# Inside case match
			if (STATE[TOP] == ST_CASE_REG) {
				if (front ~ /^;;.*/) {
					++i
					--TOP
					continue
				}
			}
			# Inside case block
			if (STATE[TOP] == ST_CASE_BLK) {
				if (ch == ")") {
					STATE[++TOP] = ST_CASE_REG
					# Output the parsed section so
					# a check is only appended if the
					# closing parentheses are followed
					# by code
					printf("%s", substr($0, 1, i))
					$0 = substr($0, i + 1)
					continue
				}
				if (front ~ /^esac([ \t#].*)?/) {
					--TOP
					i += 3
					continue
				}
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
			} else if (front ~ /^case[ \t].+[ \t]in([ \t#].*)?/) {
				STATE[++TOP] = ST_CASE_BLK
			}
		}
		# About to get the next line, print this one
		if (!(STATE[TOP] in REG_STATES)) {
			print
		}
	} while (!(STATE[TOP] in REG_STATES) && getline > 0)
}

# Do not append error checks to lines not ending in a command.
/((^|then|else|do|[({&;])|[ \t]*\\)[ \t]*$/ {
	print
	next
}

# Append the error check.
{
	print $0 " || bsda:test:err \"" FILENAME "\" " NR " $?"
}
