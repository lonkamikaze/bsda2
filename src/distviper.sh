test -n "$_distviper_" && return 0
readonly _distviper_=1

. ${bsda_dir:-.}/bsda_tty.sh
. ${bsda_dir:-.}/bsda_opts.sh
. ${bsda_dir:-.}/pkg_info.sh

#
# The session class for distviper.
#
bsda:obj:createClass distviper:Session \
	r:private:flags      "The flags collection" \
	r:private:term       "The terminal controller" \
	r:private:keep       "The kind of files to keep" \
	r:private:portsdir   "The PORTSDIR" \
	r:private:distdir    "The DISTDIR" \
	i:private:init       "The constructor" \
	c:private:clean      "The destructor" \
	x:private:params     "Process command line arguments" \
	x:private:help       "Print usage message" \
	x:private:status     "Print status" \
	x:private:getMakeVar "Retrieve variables from make" \
	x:private:run        "Select files and delete them"

#
# Set up the session and run it.
#
# @param @
#	Command line arguments
#
distviper:Session.init() {
	# Setup terminal manager
	bsda:tty:Async ${this}term

	# Set default mode
	setvar ${this}keep all

	# Read command line arguments
	bsda:opts:Flags ${this}flags
	$this.params "$@"

	# Perform
	$this.run
}

#
# The destructor.
#
# Clean up the flags and the terminal controller.
#
distviper:Session.clean() {
	$($this.getFlags).delete
	$($this.getTerm).delete
}

#
# Parse command line arguments.
#
# @param @
#	The command line arguments
#
distviper:Session.params() {
	local options flags option term

	$this.getTerm term

	bsda:opts:Options options \
	DEMO        -d --demo        'Just print what would have been done' \
	HELP        -h --help        'Display the list of command arguments' \
	INTERACTIVE -i --interactive 'Ask for confirmation before deleting' \
	NOCHKSUM    -n --no-checksum 'Skip checksum checks' \
	QUIET       -q --quiet       'Do not print anything' \
	VERBOSE     -v --verbose     'Verbose output'

	$this.getFlags flags
	while [ $# -gt 0 ]; do
		$options.getopt option "$1"
		case "$option" in
		HELP)
			$this.help "$options"
		;;
		OPT_UNKNOWN)
			$term.stderr "Unknown parameter \"$1\"."
			exit 1
		;;
		OPT_SPLIT)
			local arg
			arg="$1"
			shift
			set -- "${arg%${arg#-?}}" "-${arg#-?}" "$@"
			continue
		;;
		OPT_NOOPT)
			# Assume this is a mode
			$flags.add KEEP
			setvar ${this}keep "$1"
			if $flags.check KEEP -gt 1; then
				$term.stderr "Too many arguments: ... $@"
				exit 3
			fi
		;;
		*)
			# Catch all the flags
			$flags.add "$option"
		;;
		esac
		shift
	done

	if $flags.check VERBOSE -ne 0 && $flags.check QUIET -ne 0; then
		$term.stderr "Conflicting options -v and -q supplied."
		exit 1
	fi

	if $flags.check QUIET -eq 0; then
		$term.use 1
	fi

	$this.getMakeVar ${this}portsdir PORTSDIR
	$this.getMakeVar ${this}distdir DISTDIR

	local keep
	$this.getKeep keep
	case "$keep" in
	all | installed)
		# Usual modes
	;;
	fast)
		setvar ${this}keep installed
		$flags.add NOCHKSUM
	;;
	thorough)
		setvar ${this}keep all
	;;
	*)
		$term.stderr "Unknown category of files to keep: $keep"
		exit 2
	;;
	esac
}

#
# Print usage message.
#
# @param &1
#	A reference to a bsda:opts:Options instance
#
distviper:Session.help() {
	local usage
	$1.usage usage "\t%.2s, %-13s  %s\n"
	$($this.getTerm).stdout "usage: distviper [-dhinqv] [keep]
$(echo -n "$usage" | /usr/bin/sort -f)"
	exit 0
}

#
# Puts a message on the terminal.
#
# In verbose mode it is printed on stdout, otherwise the status line
# is updated.
#
# @param 1
#	The status message
#
distviper:Session.status() {
	local term
	$this.getTerm term
	if $($this.getFlags).check VERBOSE -ne 0; then
		$term.stdout "$1"
	else
		$term.line 0 "$1"
	fi
}

#
# Pull a variable from make.
#
# Return a variable from /usr/share/mk/bsd.port.mk.
#
# @param &1
#	The variable to return the value to
# @param 2
#	The name of the make variable to get
#
distviper:Session.getMakeVar() {
	local term value
	$this.getTerm term
	if ! value="$(/usr/bin/make -f/usr/share/mk/bsd.port.mk \
	                            -V"$2" 2>&1)"; then
		$term.stderr "make -V$2 failed:"
		$term.stderr "$value"
		exit 1
	fi
	if [ ! -d "$value" ]; then
		$term.stderr "The $2 '$value' is not a directory."
		exit 1
	fi
	$caller.setvar $1 "$value"
}

#
# A static method retrieve file|chksum pairs.
#
# @param @
#	The folders to search for distinfo files
#
distviper:Session.run_find() {
	/usr/bin/find "$@" -name distinfo -exec cat '{}' + \
	| /usr/bin/awk '
		/^SHA/ {
			sub(/^\(/, "", $2)
			sub(/\)$/, "", $2)
			pair = $2 "|" $4
			if (!(pair in pairs)) {
				pairs[pair]
				print pair
			}
		}' | /usr/bin/sort
}

#
# Static method outputting file|chksum pairs for all ports.
#
# @param portsdir
#	The PORTSDIR
#
distviper:Session.run_find_all() {
	$class.run_find "$portsdir"
}

#
# Static method outputting file|chksum pairs for installed ports.
#
# @param portsdir
#	The PORTSDIR
#
distviper:Session.run_find_installed() {
	cd "$portsdir"
	$class.run_find $(pkg:info:origins)
}

#
# Static method outputting the present distfiles.
#
# @param distdir
#	The DISTDIR
#
distviper:Session.run_find_present() {
	/usr/bin/find -s "$distdir" -type f | /usr/bin/sed "s|^$distdir/||"
}

#
# Select and delete obsolete distfiles.
#
distviper:Session.run() {
	local IFS term flags keep portsdir distdir keepSums keepFiles
	IFS='
'
	$this.getTerm term
	$this.getFlags flags
	$this.getKeep keep
	$this.getPortsdir portsdir
	$this.getDistdir distdir

	$this.status "Creating a list of $keep distfiles and their checksums"
	keepSums="$($class.run_find_$keep)"
	$this.status "Extracting a list of $keep distfiles"
	keepFiles="$(echo "$keepSums" | /usr/bin/sed 's/|.*//')"

	$this.status "Creating a list of distfiles to delete"
	local verify files file obsoleteFiles mismatchFiles chksum fcount i fmt
	verify=
	$flags.check NOCHKSUM -eq 0 && verify=1
	obsoleteFiles=
	mismatchFiles=
	files="$($class.run_find_present)"
	fcount=$(($(echo "$files" | /usr/bin/wc -w)))
	fmt="Checking file %${#fcount}d of $fcount: %s"
	for file in $files; do
		i=$((i + 1))
		$term.line 0 "$(printf "$fmt" $i "$file")"
		if ! echo "$keepFiles" | /usr/bin/grep -qFx "$file"; then
			obsoleteFiles="${obsoleteFiles:+$obsoleteFiles$IFS}$file"
			continue
		fi
		test -z "$verify" && continue

		chksum="$(/sbin/sha256 < "$distdir/$file")"
		if ! echo "$keepSums" | /usr/bin/grep -qFx "$file|$chksum"; then
			mismatchFiles="${mismatchFiles:+$mismatchFiles$IFS}$file"
			continue
		fi
	done
	$term.deactivate

	# Perform deletions
	local rmcmd rmflags
	rmcmd=/bin/rm
	rmflags="-f"
	if $flags.check INTERACTIVE -eq 0; then
		# !interactive && !quiet => -v
		$flags.check QUIET -eq 0 && rmflags="$rmflags$IFS-v"
	else
		# interactive => -i
		rmflags="$rmflags$IFS-i"
	fi

	if $flags.check DEMO -ne 0; then
		rmcmd=echo
		rmflags=
	fi

	$this.status "Remove obsolete files:"
	for file in $obsoleteFiles; do
		$rmcmd $rmflags "$distdir/$file"
	done
	$this.status "Remove files with checksum mismatches:"
	for file in $mismatchFiles; do
		$rmcmd $rmflags "$distdir/$file"
	done

	return 0
}
