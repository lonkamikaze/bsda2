test -n "$_distviper_" && return 0
readonly _distviper_=1

. ${bsda_dir:-.}/bsda_tty.sh
. ${bsda_dir:-.}/bsda_opts.sh
. ${bsda_dir:-.}/pkg_info.sh
. ${bsda_dir:-.}/bsda_bsdmake.sh

#
# The session class for distviper.
#
bsda:obj:createClass distviper:Session \
	a:private:Flags=bsda:opts:Flags \
	a:private:Term=bsda:tty:Terminal \
	r:private:keep       "The kind of files to keep" \
	r:private:portsdir   "The PORTSDIR" \
	r:private:distdir    "The DISTDIR" \
	i:private:init       "The constructor" \
	x:private:params     "Process command line arguments" \
	x:private:help       "Print usage message" \
	x:private:error      "Print error message" \
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
	bsda:tty:Terminal ${this}Term

	# Set default mode
	setvar ${this}keep all

	# Read command line arguments
	bsda:opts:Flags ${this}Flags
	$this.params "$@" || return $?

	# Perform
	$this.run
}

#
# Parse command line arguments.
#
# @param @
#	The command line arguments
#
distviper:Session.params() {
	local options flags option term

	$this.Term term

	bsda:opts:Options options \
	DEMO        -d --demo        'Just print what would have been done' \
	HELP        -h --help        'Display the list of command arguments' \
	INTERACTIVE -i --interactive 'Ask for confirmation before deleting' \
	NOCHKSUM    -n --no-checksum 'Skip checksum checks' \
	QUIET       -q --quiet       'Do not print anything' \
	VERBOSE     -v --verbose     'Verbose output'
	$caller.delete $options

	$this.Flags flags
	while [ $# -gt 0 ]; do
		$options.getopt option "$1"
		case "$option" in
		HELP)
			$this.help "$options"
		;;
		OPT_UNKNOWN)
			$this.error "Unknown parameter \"$1\"."
			return 1
		;;
		OPT_SPLIT)
			eval "$bsda_opts_split"
			continue
		;;
		OPT_NOOPT)
			# Assume this is a mode
			$flags.add KEEP
			setvar ${this}keep "$1"
			if $flags.check KEEP -gt 1; then
				$this.error "Too many arguments: ... $@"
				return 3
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
		$this.error "Conflicting options -v and -q supplied."
		return 1
	fi

	if $flags.check QUIET -eq 0; then
		$term.use 1
	fi

	$this.getMakeVar ${this}portsdir PORTSDIR || return $?
	$this.getMakeVar ${this}distdir DISTDIR || return $?

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
		$this.error "Unknown category of files to keep: $keep"
		return 2
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
	$($this.Term).stdout "usage: distviper [-dhinqv] [keep]
$(echo -n "$usage" | /usr/bin/sort -f)"
	exit 0
}

#
# Print error message.
#
# @param *
#	The message to print
#
distviper:Session.error() {
	$($this.Term).stderr "${0##*/}: $*"
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
	$this.Term term
	if $($this.Flags).check VERBOSE -ne 0; then
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
# @retval 0
#	The variable was successfully acquired
# @retval 1
#	The variable is not a directory
#
distviper:Session.getMakeVar() {
	local term value
	$this.Term term
	if ! value="$(bsda:bsdmake -f/usr/share/mk/bsd.port.mk \
	                           -V"$2" 2>&1)"; then
		$this.error "$bsda_bsdmake -V$2 failed:"
		$term.stderr "$value"
		return 1
	fi
	if [ ! -d "$value" ]; then
		$this.error "The $2 '$value' is not a directory."
		return 1
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
	/usr/bin/find "$@" -type f -name distinfo -not -exec /usr/bin/awk '
		/^SHA/ {
			sub(/^\(/, "", $2)
			sub(/\)$/, "", $2)
			pair = $2 "|" $4
			if (!(pair in pairs)) {
				pairs[pair]
				print pair
			}
		}' '{}' + 2>&1 | /usr/bin/sort
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
	IFS=$'\n'
	$this.Term term
	$this.Flags flags
	$this.getKeep keep
	$this.getPortsdir portsdir
	$this.getDistdir distdir

	$this.status "Creating a list of $keep distfiles"
	keepSums="$($class.run_find_$keep)"
	keepFiles="$(echo "$keepSums" | /usr/bin/sed 's/|.*//')"

	if echo "$keepSums" | /usr/bin/grep -qv '|[0-9a-f]*$'; then
		$this.error "Access to $portsdir failed"
		$term.stderr "$(echo "$keepSums" | /usr/bin/grep -v '|[0-9a-f]*$')"
		exit 1
	fi

	$this.status "Creating a list of distfiles to delete"
	local verify files file obsoleteFiles mismatchFiles chksum fcount i fmt
	verify=
	$flags.check NOCHKSUM -eq 0 && verify=1
	log obsoleteFiles=
	log mismatchFiles=
	files="$($class.run_find_present)"
	fcount=$(($(echo "$files" | /usr/bin/wc -w)))
	fmt="Checking file %${#fcount}d of $fcount: %s"
	i=0
	for file in $files; do
		i=$((i + 1))
		$term.line 0 "$(printf "$fmt" $i "$file")"
		if ! echo "$keepFiles" | /usr/bin/grep -qFx "$file"; then
			log obsoleteFiles.push_back "$file"
			continue
		fi
		test -z "$verify" && continue

		chksum="$(/sbin/sha256 < "$distdir/$file")"
		if ! echo "$keepSums" | /usr/bin/grep -qFx "$file|$chksum"; then
			log mismatchFiles.push_back "$file"
			continue
		fi
	done
	$term.deactivate

	# Perform deletions
	local rmcmd rmflags
	rmcmd=/bin/rm
	log rmflags= -f
	if $flags.check INTERACTIVE -eq 0; then
		# !interactive && !quiet => -v
		$flags.check QUIET -eq 0 && log rmflags.push_back -v
	else
		# interactive => -i
		log rmflags.push_back -i
	fi

	if $flags.check DEMO -ne 0; then
		rmcmd=echo
		log rmflags=
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
