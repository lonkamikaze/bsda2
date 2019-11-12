test -n "$_pkg_validate_" && return 0
readonly _pkg_validate_=1

. ${bsda_dir:-.}/bsda_tty.sh
. ${bsda_dir:-.}/bsda_fifo.sh
. ${bsda_dir:-.}/pkg_options.sh
. ${bsda_dir:-.}/pkg_info.sh
. ${bsda_dir:-.}/pkg_query.sh

#
# A simple class to pass job results through the FIFO.
#
# The misses attribute is a list in the format:
#	file "|" library "|" ("[direct]" | "[indirect]")
#
bsda:obj:createClass pkg:validate:JobResult \
	r:pkg    "The package name" \
	r:files  "The list of modified or inaccessible files" \
	r:sline  "The status line id this job is listed on" \
	i:init   "Constructor"

#
# A job result constructor.
#
# @param 1
#	The package name
# @param 2
#	The list of modified or inaccessible files
# @param 3
#	The status line number
#
pkg:validate:JobResult.init() {
	setvar ${this}pkg "$1"
	setvar ${this}files "$2"
	setvar ${this}sline "$3"
}

#
# The session class for pkg_validate.
#
bsda:obj:createClass pkg:validate:Session \
	a:private:Flags=bsda:opts:Flags \
	a:private:Term=bsda:tty:Async \
	a:private:Fifo=bsda:fifo:Fifo \
	r:private:packages "The list of packages to process" \
	r:private:jobs     "The number of parallel jobs" \
	i:private:init     "The constructor" \
	x:private:params   "Parse command line arguments" \
	x:private:help     "Print usage message" \
	x:private:packages "Determine requested packages" \
	x:private:run      "Fork library checks" \
	x:private:print    "Print a serialised JobResult instance" \
	x:private:job      "Perform library checks"

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
	$($this.Term).use $(($($this.getJobs) + 1))

	# Create the fifo
	bsda:fifo:Fifo ${this}Fifo

	# Perform checks
	$this.run
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
# Print a serialised JobResult instances.
#
# @param &1
#	The status line id used for this job
# @param 2
#	The serialised JobResult
#
pkg:validate:Session.print() {
	local res flags pkg files IFS output msg file hash
	bsda:obj:deserialise res "$2"
	$caller.setvar "$1" "$($res.getSline)"

	$this.Flags flags

	$res.getPkg pkg
	$res.getFiles files
	$res.delete

	# Only mention permission issues in verbose mode
	if $flags.check VERBOSE -eq 0; then
		files="$(echo "$files" | /usr/bin/grep -Ev '^perm\|')"
	fi

	test -z "$files" && return

	# Honour quiet output flag
	if $flags.check PKG_QUIET -ne 0; then
		$($this.Term).stdout "$pkg"
		return $?
	fi

	# Give a detailed account of every modified or inaccessible file
	IFS=$'\n'
	output=
	for file in $files; {
		msg=
		case "$file" in
		perm\|*)
			msg="user ${USER} has no permission to access"
		;;
		miss\|*)
			msg="missing file"
		;;
		checksum/*\|*)
			hash="${file%%|*}"
			hash="${hash#*/}"
			msg="mismatched $hash checksum for"
		;;
		hash/*\|*)
			hash="${file%%|*}"
			hash="${hash#*/}"
			msg="unsupported $hash checksum for"
		;;
		*)
			$($this.Term).stderr "${0##*/}: internal error, job returned: '$file'"
			continue
		;;
		esac
		output="${output}${pkg}: ${msg} ${file#*|}${IFS}"
	}
	$($this.Term).stdout ${output}
}

#
# Fork off missing library checks and collect results.
#
pkg:validate:Session.run() {
	local IFS pkg pkgs result maxjobs jobs term fmt count num fifo

	# Initialise dispatcher
	IFS=$'\n'

	$this.Term term
	$this.getJobs maxjobs
	$this.getPackages pkgs
	$this.Fifo fifo
	num=$(($(echo "$pkgs" | /usr/bin/wc -l)))
	        # Total number of packages/jobs
	count=0 # Completed jobs
	jobs=0  # Number of running jobs
	sline=1 # The next status line to use

	#
	# Dispatch jobs
	#
	fmt="Jobs done: %${#num}d of $num"
	$term.line 0 "$(printf "$fmt" $count)"
	while [ -n "$pkgs" ]; do
		# Wait for jobs to complete
		if [ $jobs -ge $maxjobs ]; then
			# Blocking read
			$fifo.source read -r result
			jobs=$((jobs - 1))
			$this.print sline "$result"
			count=$((count + 1))
			$term.line 0 "$(printf "$fmt" $count)"
		fi
		# Select next package to process
		pkg="${pkgs%%$IFS*}"
		# Dispatch job
		(
			bsda:obj:fork
			$this.job "$pkg" $sline
		) &
		$term.line $sline "$pkg"
		pkgs="${pkgs#$pkg}"
		pkgs="${pkgs#$IFS}"
		jobs=$((jobs + 1))
		sline=$((sline + 1))
	done

	#
	# Wait for last jobs
	#
	fmt="Waiting for %${#maxjobs}d job(s)"
	while [ $jobs -gt 0 ]; do
		# Blocking read
		$fifo.source read -r result
		$this.print sline "$result"
		$term.line $sline
		jobs=$((jobs - 1))
		count=$((count + 1))
		$term.line 0 "$(printf "$fmt" $jobs)"
	done
}

#
# Validate a single file
#
# @param 1
#	The queried file hash
# @param 2
#	The queried file name
# @param files
#	Updated if the current file is inaccessible or has a checksum
#	mismatch
#
pkg:validate:Session:job() {
	local sum hash
	sum="${1#*\$}"
	hash=
	case "$1" in
	1\$*)
		hash=sha256
	;;
	esac
	if [ -z "$hash" -o ! -x "/sbin/$hash" ]; then
		# unsupported hash
		files="${files}hash/$hash|$2${IFS}"
		return
	elif [ -L "$2" ]; then
		local link
		# symlink
		link="$(/usr/bin/readlink -n "$2")"
		# Pkgng removes the leading /, and appends
		# a 0 byte. The latter was originally by
		# accident, but will forever remain in order
		# to not break existing packages.
		if [ -z "${link##/*}" ]; then
			link="${link#/}\\0"
		fi
		sum="$(printf "$link" | /sbin/$hash -q)"
	elif [ ! -e "$2" ]; then
		# file does not exist
		files="${files}miss|$2${IFS}"
	elif [ ! -r "$2" ]; then
		# file or location not accessible
		files="${files}perm|$2${IFS}"
		return
	else
		# regular file hash
		sum="$(/sbin/$hash -q "$2")"
	fi
	# sum is set to the correct hash in case the file has the
	# correct hash or a problem was already reported
	if [ "$sum" != "${1#*\$}" ]; then
		files="${files}checksum/$hash|$2${IFS}"
	fi
}

#
# Check files in a package for missing libraries.
#
# @param 1
#	The package to check
# @param 2
#	The status line this job is listed on
#
pkg:validate:Session.job() {
	local IFS files res
	# The files of the package
	IFS=$'\n'
	eval "$(pkg:query:select "$class:job '%Fs' '%Fp'" $1)"

	# Create a JobResult, serialise it and send it back to the dispatcher
	pkg:validate:JobResult res "$1" "$files" "$2"
	$($this.Fifo).sink $res.serialise
}
