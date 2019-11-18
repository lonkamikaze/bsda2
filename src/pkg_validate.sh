test -n "$_pkg_validate_" && return 0
readonly _pkg_validate_=1

. ${bsda_dir:-.}/bsda_tty.sh
. ${bsda_dir:-.}/bsda_fifo.sh
. ${bsda_dir:-.}/pkg_options.sh
. ${bsda_dir:-.}/pkg_info.sh
. ${bsda_dir:-.}/pkg_query.sh

#
# The session class for pkg_validate.
#
bsda:obj:createClass pkg:validate:Session \
	a:private:Flags=bsda:opts:Flags \
	a:private:Term=bsda:tty:Async \
	a:private:Fifo=bsda:fifo:Fifo \
	r:private:packages "The list of packages to process" \
	r:private:jobs     "The number of parallel jobs" \
	r:private:jobpids  "The active job pids" \
	i:private:init     "The constructor" \
	c:private:clean    "The destructor" \
	x:private:params   "Parse command line arguments" \
	x:private:help     "Print usage message" \
	x:private:packages "Determine requested packages" \
	x:private:run      "Fork file checks" \
	x:private:job      "Perform file checks"

#
# Constructor for a pkg_validate session.
#
# @param @
#	The command line arguments
#
pkg:validate:Session.init() {
	# Setup terminal manager
	bsda:tty:Async ${this}Term

	# Set defaults
	setvar ${this}jobs $(/sbin/sysctl -n hw.ncpu 2>&- || echo 1)

	# Read command line arguments
	bsda:opts:Flags ${this}Flags
	$this.params "$@"

	# Setup terminal lines
	$($this.Term).use 1

	# Create the fifo
	bsda:fifo:Fifo ${this}Fifo

	# Perform checks
	$this.run
}

#
# Harvest worker processes.
#
pkg:validate:Session.clean() {
	local IFS fifo pids pid
	IFS=$'\n'
	$this.Fifo fifo
	$this.getJobpids pids
	for pid in $pids; do
		$fifo.sink echo return
	done
	wait $pids
	return 0
}

#
# Parse command line arguments.
#
# @param @
#	The command line arguments
#
pkg:validate:Session.params() {
	local options flags nl option

	bsda:opts:Options options
	$caller.delete $options
	pkg:options:append $options
	$options.append \
	CLEAN     -c  --clean     'Turn off progress output' \
	HELP      -h  --help      'Display the list of command arguments' \
	JOBS      -j* --jobs      'Number of parallel jobs' \
	VERBOSE   -v  --verbose   'Verbose output'

	$this.Flags flags

	nl=$'\n'

	while [ $# -gt 0 ]; do
		$options.getopt option "$1"
		case "$option" in
		PKG_* | CLEAN | VERBOSE)
			$flags.add "$option"
		;;
		HELP)
			$this.help "$options"
		;;
		JOBS)
			local jobs
			jobs="${1#-j}"
			jobs="${jobs#--jobs}"
			if [ -z "$jobs" ]; then
				jobs="$2"
				shift
			fi
			if ! [ "$jobs" -eq "$jobs" ] 2>&-; then
				$($this.Term).stderr \
					"The -j option must be followed by a number."
				exit 4
			elif [ "$jobs" -lt 1 ]; then
				$($this.Term).stderr \
					"The -j option must specify at least 1 job."
				exit 4
			else
				setvar ${this}jobs $jobs
			fi
		;;
		OPT_UNKNOWN)
			$($this.Term).stderr "Unknown parameter \"$1\"."
			exit 2
		;;
		OPT_SPLIT)
			local arg
			arg="$1"
			shift
			set -- "${arg%${arg#-?}}" "-${arg#-?}" "$@"
			continue
		;;
		OPT_NOOPT)
			# Discontinue argument processing when a
			# noopt is encountered
			break
		;;
		esac
		shift
	done

	if $flags.check CLEAN -ne 0; then
		$($this.Term).deactivate
	fi

	if $flags.check VERBOSE -ne 0 && $flags.check PKG_QUIET -ne 0; then
		$($this.Term).stderr \
			"The parameters -v and -q may not be used at the same time."
		exit 3
	fi

	# Use the remaining arguments to query for packages
	$this.packages "$@"
}

#
# Print usage message.
#
pkg:validate:Session.help() {
	local usage
	$1.usage usage "\t%.2s, %-18s  %s\n"
	$($this.Term).stdout "usage: pkg_validate [-aCcdghiOoqrvx] [-j jobs] [pkg-name]
$(echo -n "$usage" | /usr/bin/sort -f)"
	exit 0
}

#
# Take the list of requested packages and turn it into a list of package
# names.
#
# The resulting list of packages is stored in the packages attribute.
#
# @param @
#	A list of package queries
#
pkg:validate:Session.packages() {
	local pkginfo flags pkgs warn
	$this.Flags flags
	pkg:info:Env pkginfo $flags
	$caller.delete $pkginfo

	# Call pkg-info to acquire a list of packages
	if ! $pkginfo.match pkgs "$@"; then
		local errmsg errnum
		$pkginfo.getErrmsg errmsg
		$pkginfo.getErrnum errnum
		$($this.Term).stderr "$errmsg"
		exit $errnum
	fi

	$pkginfo.getWarn warn
	if [ -n "$warn" ]; then
		$($this.Term).stderr "$warn"
	fi

	# Verbose output
	if $flags.check VERBOSE -ne 0; then
		if $flags.check PKG_ALL -ne 0; then
			$($this.Term).stderr "Checking all packages ..."
		else
			local IFS
			IFS=$'\n'
			$($this.Term).stderr "Checking packages:" \
			                     "------------------" \
			                     "$pkgs" \
			                     "------------------"
		fi
	fi

	setvar ${this}packages "$pkgs"
}

#
# Fork off missing library checks and collect results.
#
pkg:validate:Session.run() {
	local IFS pkg pkgs maxjobs jobs term fmt count num fifo jobpids
	local line

	# Initialise dispatcher
	IFS=$'\n'

	$this.Term term
	$this.getJobs maxjobs
	$this.getPackages pkgs
	$this.Fifo fifo

	#
	# Dispatch jobs
	#
	jobs=0  # Number of running jobs
	jobpids=
	while [ $((jobs += 1)) -le $((maxjobs)) ]; do
		# Dispatch job
		(
			bsda:obj:fork
			$this.job
		) &
		jobpids="${jobpids}$!${IFS}"
		setvar ${this}jobpids "$jobpids"
	done

	num=$(($(echo "$pkgs" | /usr/bin/wc -l)))
	        # Total number of packages/jobs
	count=0 # Completed packages
	fmt="Checking package %${#num}d of $num: %s"
	while kill -0 $jobpids 2>&- && [ -n "$pkgs" ]; do
		# Select next package to process
		count=$((count + 1))
		pkg="${pkgs%%$IFS*}"
		$term.line 0 "$(printf "$fmt" $count "$pkg")"
		$fifo.sink "pkg:query:select \"$class:job '$pkg' '%Fs' '%Fp'\" $pkg"
		pkgs="${pkgs#$pkg}"
		pkgs="${pkgs#$IFS}"
	done
	if ! kill -0 $jobpids 2>&-; then
		$term.stderr "${0##*/}: ERROR: worker process died unexpectedly"
	fi
}

#
# Validate a single file.
#
# @param 1
#	The package name
# @param 2
#	The queried file hash
# @param 3
#	The queried file name
# @param flags
#	A bsda:opts:Flags instance
#
pkg:validate:Session:job() {
	local sum hash msg
	sum="${2#*\$}"
	hash=
	msg=
	case "$2" in
	1\$*)
		hash=sha256
	;;
	esac
	if [ -z "$hash" -o ! -x "/sbin/$hash" ]; then
		msg="unsupported $hash checksum for"
	elif [ -L "$3" ]; then
		local link
		# symlink
		link="$(/usr/bin/readlink -n "$3")"
		# Pkgng removes the leading /, and appends
		# a 0 byte. The latter was originally by
		# accident, but will forever remain in order
		# to not break existing packages.
		if [ -z "${link##/*}" ]; then
			link="${link#/}\\0"
		fi
		sum="$(printf "$link" | /sbin/$hash -q)"
	elif [ ! -e "$3" ]; then
		msg="missing file"
	elif [ ! -r "$3" ]; then
		# file or location not accessible
		if $flags.check VERBOSE -ne 0; then
			msg="user ${USER} has no permission to access"
		fi
	else
		# regular file hash
		sum="$(/sbin/$hash -q "$3")"
	fi
	# sum is set to the correct hash in case the file has the
	# correct hash or a problem was already reported
	if [ "$sum" != "${2#*\$}" ]; then
		msg="mismatched $hash checksum for"
	fi
	if [ -n "${msg}" ]; then
		$term.stdout "$1: ${msg} $3"
	fi
}

#
# Check files in a package for missing libraries.
#
pkg:validate:Session.job() {
	local line flags
	$this.Flags flags
	while $fifo.source read -r line; do
		eval "$line"
	done
}