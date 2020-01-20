# Get the order of options
BEGIN {
	OPTION_STR["DOCS"] =     "%%PORTDOCS%%"
	OPTION_STR["EXAMPLES"] = "%%PORTEXAMPLES%%"
	for (i = 1; i < ARGC; ++i) {
		OPTIONS_ORDERD[i] = ARGV[i]
		CNT_OPT_FILES[ARGV[i]] = 0
		if (!(ARGV[i] in OPTION_STR)) {
			OPTION_STR[ARGV[i]] = "%%" ARGV[i] "%%"
		}
		if (!("NO_" ARGV[i] in OPTION_STR)) {
			OPTION_STR["NO_" ARGV[i]] = "%%NO_" ARGV[i] "%%"
		}
		delete ARGV[i]
	}
	CNT_FILES = 0
}
# Get the options the following files were staged with
/^OPTIONS:/ {
	delete aoptions
	sub(/^OPTIONS: */, "")
	cnt_aoptions = split($0, aoptions)
	for (i = 1; i <= cnt_aoptions; ++i) {
		++OPTIONS[aoptions[i]]
	}
	++CONFIGS
	next
}
# Collect files
{
	# Record order of file
	if (!($0 in FILES)) {
		FILES_ORDERED[++CNT_FILES] = $0
	}
	# Count occurence of file
	++FILES[$0]
	# The same book keepin per option
	for (i = 1; i <= cnt_aoptions; ++i) {
		option = aoptions[i]
		# Record order of file for option
		if (!OPT_FILES[option, $0]) {
			OPT_FILES_ORDERED[option, ++CNT_OPT_FILES[option]] = $0
		}
		# Count occurence of file by option
		++OPT_FILES[option, $0]
	}
}
# Print files
END {
	# Print files common to all configurations
	for (i = 1; i <= CNT_FILES; ++i) {
		file = FILES_ORDERED[i]
		if (FILES[file] == CONFIGS) {
			print file
			delete FILES[file]
		}
	}
	# Print option specific files
	for (i = 1; OPTIONS_ORDERD[i]; ++i) {
		option = OPTIONS_ORDERD[i]
		for (p = 1; p <= CNT_OPT_FILES[option]; ++p) {
			file = OPT_FILES_ORDERED[option, p]
			# Skip files that have already been printed
			if (!(file in FILES)) { continue }
			# Print file if it only occurs for the current
			# option
			if (OPT_FILES[option, file] == OPTIONS[option] &&
			    OPT_FILES[option, file] == FILES[file]) {
				print OPTION_STR[option] file
				delete FILES[file]
			}
		}
		for (p = 1; p <= CNT_FILES; ++p) {
			file = FILES_ORDERED[p]
			if (!(file in FILES)) { continue }
			# Print file if it occurs everywhere but with
			# this option
			if (!OPT_FILES[option, file] &&
			    FILES[file] + OPTIONS[option] == CONFIGS) {
				print OPTION_STR["NO_" option] file
				delete FILES[file]
			}
		}
	}
	# Print all files that have not been printed
	for (i = 1; i <= CNT_FILES; ++i) {
		file = FILES_ORDERED[i]
		if (!(file in FILES)) { continue }
		print "@fail " file " could not be mapped to an option!"
		msg = "@fail Candidates:"
		for (p = 1; OPTIONS_ORDERD[p]; ++p) {
			if (OPT_FILES[OPTIONS_ORDERD[p], file]) {
				msg = msg " " OPTIONS_ORDERD[p]
			}
		}
		print msg
	}
}
