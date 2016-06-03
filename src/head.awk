#!%%AWK%% -f
#
# Outputs a given number of lines, unlike head(1) lines are counted as they
# appear on the terminal.
#
# The properties of the terminal have to be supplied as parameters.
#
# Supports single spaced UTF-8 multibyte characters if LANG is set accordingly.
#
# @param 1
#	The number of terminal columns "tput co".
# @param 2
#	The number of terminal lines to output.
# @param 3
#	The tab stop width "tput it".
# @param 4
#	Has the newline glitch "tput xn".
#

BEGIN {
	# Use the first 4 arguments as terminal parameters.
	MAXCO = ARGV[1];
	MAXLI = ARGV[2];
	TABSTOPS = ARGV[3];
	GLITCH = ARGV[4];

	# Throw them away, so they won't be openend as files.
	for (i = 1; i <= 4; i++)
		ARGV[i] = null;

	# Open stdin if no files were given.
	if (ARGC <= 5)
		ARGV[1] = "/dev/stdin";

	# Current line.
	line = 0;
	# Current xpos.
	xpos = 0;
	# Used to eat tabs after line overflow, on terminals without the
	# newline glitch.
	eattabs = 0;

	# Don't eat new lines.
	if (ENVIRON["LANG"] ~ "\.UTF-8$")
		utf8 = 1;
}

#
# Merge UTF-8 bytes to a single char.
#
# This breaks with wide characters, if only there was a table ...
#
# This is broken by characters more than one terminal column wide (such as
# CJK characters). This cannot be solved by a table, because printing
# width depends on the font.
#
function filterUtf8(char) {
	if (utf8) {
		if (filterUtf8Expected) {
			# Collect multibyte char bytes.
			filterUtf8Expected--;
			filterUtf8Char = filterUtf8Char char;
			if (!filterUtf8Expected) {
				process(filterUtf8Char);
			}
		} else {
			if (char <= "\x7f") {
				# US-ASCII 1 byte char
				process(char);
			} else if (char <= "\xc1") {
				# Invalid char, ignore it!
			} else if (char <= "\xdf") {
				# 2-byte char
				filterUtf8Expected = 1;
				filterUtf8Char = char;
			} else if (char <= "\xef") {
				# 3-byte char
				filterUtf8Expected = 2;
				filterUtf8Char = char;
			} else if (char <= "\xf4") {
				# 4-byte char
				filterUtf8Expected = 3;
				filterUtf8Char = char;
			} else {
				# Restricted by RFC 3629, or invalid
			}
		}
	} else
		process(char);
}

#
# Calculate line and column, terminate as appropriate.
#
function process(char) {
	# Detect overflowing lines on terminals with the newline glitch.
	if (GLITCH && xpos == MAXCO) {
		line++;
		xpos = 0;
	}

	# Detect overflowing lines on newline glitch eating terminals.
	if (!GLITCH && xpos == MAXCO && char != "\n" && char != "\r" && char != "\f" && char != "\v") {
		# Eat tabs after a line overflow.
		eattabs = 1;
		# Transition into the next line.
		line++;
		xpos = 0;
	}

	# Stop when the wanted line is met.
	# But put out eaten tabs first.
	if (line >= MAXLI && !(eattabs && char == "\t")) {
		exit(0);
	}

	# Calculate the xpos, line, behind this char.
	if (char == "\n") {
		# Transition into the next line.
		line++;
		xpos = 0;
	} else if (char == "\f" || char == "\v") {
		# Form feed or vertical tab.
		line++;
		if (xpos >= MAXCO)
			xpos = MAXCO - 1;
	} else if (char == "\r") {
		# Carriage return.
		xpos = 0;
	} else if (char == "\t") {
		if (!eattabs) {
			# Calculate tab stops correctly.
			xpos = xpos - xpos % TABSTOPS + TABSTOPS + 1;
			# Tabs never lead further than the last character of a line.
			if (xpos >= MAXCO)
				xpos = MAXCO - 1;
		}
	} else if (char == "\a") {
		# Bell character, does not change cursor.
	} else if (char == "\b") {
		# Backspace
		if (xpos > 0)
			xpos--;
	} else
		xpos++;

	# Turn off tab eating.
	if (char != "\t" && char != "\a")
		eattabs = 0;

	# Finally, print the character.
	printf(char);
}

{
	split($0, chars, "");
	for (i = 1; i <= length(chars); i++)
		filterUtf8(chars[i]);
	filterUtf8("\n");
}

END {
	if (!line)
		filterUtf8("\n");

	printf("." line);
}

