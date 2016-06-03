#!%%AWK%% -f
#
# This script parses a configuration file and returns it as make syntax.
#


#
# Replaces something in a string, returns the new string.
#
# @param regexp
#	The regular expression to replace.
# @param replace
#	What to replace it with.
# @param haystack
#	The string to work on.
# @return
#	The processed string.
#
function substitute(regexp, replace, haystack) {
	sub(regexp, replace, haystack);
	return haystack;
}

##
# This selects the first string from haystack that machthes regexp.
#
# @param regexp
#	The regular expression to match.
# @param haystack
#	The string to work on.
# @return
#	The string matching regexp.
#
function grep(regexp, haystack) {
	sub(regexp, "<<BEGIN>>&<<END>>", haystack);
	sub(".*<<BEGIN>>", "", haystack);
	sub("<<END>>.*", "", haystack);
	return haystack;
}

##
# This function checks whether a string contains useable data.
#
# @param haystack
#	The string to check.
# @return
#	1 if the string contains useable data.
#
function isset(haystack) {
	if (haystack ~ "[^[:space:]]")
		return 1;
}

##
# Resolves paths at the beginning of a location pattern as
# far as possible and prints the result. The string can
# contain several paths seperated by '|' and '&'.
#
# @param path
#	The location pattern to resolve.
#
function resolvePath(path,
pattern) {
	# Find previous paths.
	# Take care of logical or connections.
	if (path ~ "\\|") {
		# Select all paths before this one.
		pattern = substitute("\\|[^\\|]*$", "", path);
		# Process the previous patterns.
		resolvePath(pattern);

		# Process the last one.
		path = grep("[^\\|]*$", path);
		printf("%s", " || ");
	}

	# Take care of logical and connections.
	if (path ~ "\\&") {
		# Select all paths before this one.
		pattern = substitute("\\&[^\\&]*$", "", path);
		# Process the previous patterns.
		resolvePath(pattern);

		# Process the last one.
		path = grep("[^\\&]*$", path);
		printf("%s", " && ");
	}

	# Trim the location pattern.
	sub("^[[:space:]]+", "", path);
	sub("[[:space:]]+$", "", path);

	# Check whether this is a pattern that should NOT be matched.
	if (path ~ "^!.*") {
		sub("^!", "", path);
		printf("%s", "!${.CURDIR:M");
	} else
		printf("%s", "${.CURDIR:M");

	# Paths that do not begin with '/' are never resolveable.
	if (path ~ "^[^/]") {
		printf("%s", path "}");
		return;
	}

	pattern = path;
	# Select the resolvable part of the given path.
	sub("[/]*[^/]*[?*].*$", "", path);
	# Remember the part that cannot be resolved.
	sub("^" path, "", pattern);

	# If there is a resolveable part resolve it.
	if (path) {
		# If path exists, resolve and print it, else print the
		# original string.
		print("printf `[ -d \"" path "\" ] && (cd \"" path "\";pwd -P) || printf \"" path "\"`") | "sh";
		close("sh");
	}

	# Append the unresolvable part.
	printf("%s", pattern "}");
}

##
# Prints the beginning of a new block.
#
# @param pattern
#	The location pattern for this block.
#
function beginBlock(pattern) {
	nesting[nesting_len++] = pattern;
	# Print the if.
	printf("%s", ".if ");

	# Print the if statement.
	resolvePath(pattern);

	# Append a newline.
	print("");
}

##
# Parses lines in quoted mode, dealing with things like ending quotes
# and single line quotes.
#
# @param line		The line to parse into a quoted string.
#
function parseQuoted(line) {
	# If the quote ends here, take care of it.
	if (line ~ "\"") {
		# Print the part that is still within the quote.
		print(substitute("\".*", "\"", line));

		# If present parse what is left of the line.
		sub("[^\"]*\"", "", line);
		if (isset(line))
			return parse(line);

		# Or end here, if there is nothing left to parse.
		return;
	}

	# Lines that are in a quoted block do not get parsed.
	print(line);
	return 1;
}

##
# Parses a line of buildflags.conf file.
#
# @param line		The line to parse.
# @param quoted		Set to true if the line is part of a
#			quoted string.
# @return		Whether the next line should be parsed in
#			quoted mode.
#
function parse(line, quoted,
block) {
	# Lines in a quoted block only get parsed for the end of the block.
	if (quoted)
		return parseQuoted(line);

	# Spaces at the beginning are never required.
	sub("^[[:space:]]+", "", line);

	# Deal with comments. Comments behind parseable data will end up
	# in the line in front of that data.
	if (line ~ "^[^\"]*#") {
		# Print the comment.
		print(grep("#.*", line));

		# Parse whatever was before the comment.
		sub("#.*", "", line);
		if (isset(line))
			parse(line);

		return;
	}

	# Deal with make native directives.
	if (line ~ "^\\.") {
		print(line);
		return;
	}

	# Deal with quotes.
	if (line ~ "\"") {
		# Check whether the assignment is properly formated.
		if (line ~ "[^[:space:]{}]+=[[:space:]]*\"") {
			# Take whatever is in front of the assignment
			# and parse it.
			block = substitute("[^[:space:]{}]+=[[:space:]]*\".*", "", line);
			if (isset(block))
				parse(block);
		} else
			printf("%s", ".error ");

		# Print the variable assignment in front of the quoted string.
		block = grep("[^[:space:]{}]+=[[:space:]]*\"", line);
		printf("%s", block);

		# Parse the quoted string.
		block = substitute("[^\"]*\"", "", line);
		return parseQuoted(block);
	}

	# Close a block.
	if (line ~ "}") {
		# Parse whatever is before the end of the block.
		block = substitute("}.*", "", line);
		if (isset(block))
			parse(block);

		# End the block.
		print(".endif # " nesting[--nesting_len]);

		# Parse whatever is behind the end of the block.
		sub("[^}]*}", "", line);
		if (line ~ "[^[:space:]]")
			parse(line);

		return;
	}

	# Begin a new block.
	if (line ~ "{") {
		# Open the new block.
		beginBlock(substitute("{.*", "", line));

		# Pase whatever is inside.
		sub("[^{]*{", "", line);
		if (isset(line))
			parse(line);

		return;
	}

	# Deal with compact variable assignments.
	if (line ~ "^[^[:space:]=]+=[^[:space:]]+") {
		# Print the assignment.
		print(grep("^[^[:space:]=]+=[^[:space:]]+", line));

		# Parse what follows.
		block = substitute("^[^[:space:]=]+=[^[:space:]]+", "", line);
		if (isset(block))
			parse(block);

		return;
	}

	# Deal with long variable assignments.
	if (line ~ "^[^[:space:]]+=") {
		# Print the whole line.
		print(line);
		return;
	}

	# Deal with negated flags.
	if (line ~ "^![^[:space:]=]+") {
		# Remove the negation symbol.
		line = substitute("^!", "", line);
		# Print the undefine command.
		print(".undef " grep("^[^[:space:]=]+", line));

		# Parse what follows.
		block = substitute("^[^[:space:]=]+", "", line);
		if (isset(block))
			parse(block);

		return;
	}

	# Deal with flags.
	if (line ~ "^[^[:space:]=]+") {
		# Print the flag.
		printf("%-23s %s", grep("^[^[:space:]=]+", line) "=", "yes\n");

		# Parse what follows.
		block = substitute("^[^[:space:]=]+", "", line);
		if (isset(block))
			parse(block);

		return;
	}

	# Print empty lines.
	if (!isset(line))
		print("");
}

{
	# Parse the file by line.
	quoted = parse($0, quoted);
}
