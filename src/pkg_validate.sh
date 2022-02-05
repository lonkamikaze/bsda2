test -n "$_pkg_validate_" && return 0
readonly _pkg_validate_=1

. ${bsda_dir:-.}/bsda_async.sh
. ${bsda_dir:-.}/bsda_tty.sh
. ${bsda_dir:-.}/bsda_fifo.sh
. ${bsda_dir:-.}/pkg_options.sh
. ${bsda_dir:-.}/pkg_info.sh
. ${bsda_dir:-.}/pkg_query.sh

#
# Create an asynchronous Terminal class.
#
bsda:async:createClass bsda:tty:Async bsda:tty:Terminal

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
	local pids
	$this.getJobpids pids
	if [ -n "$pids" ]; then
		kill $pids 2>&-
		wait $pids
	fi
	return 0
}

#
# Parse command line arguments.
#
# @param @
#	The command line arguments
#
pkg:validate:Session.params() {
	local options flags option e msg

	bsda:err:collect
	bsda:opts:Flags ${this}Flags DEVELOPER
	$this.Flags flags

	while bsda:err:get e msg; do
		case "$e" in
		E_BSDA_OPTS_ENV)
			$($this.Term).stderr "$msg"
		;;
		*)
			bsda:err:forward "$e" "$msg"
		;;
		esac
	done

	bsda:opts:Options options
	$caller.delete $options
	pkg:options:append $options
	$options.append \
	CLEAN     -c  --clean     'Turn off progress output' \
	DEVELOPER -D  --developer 'Produce messages for ports/pkg developers' \
	HELP      -h  --help      'Display the list of command arguments' \
	JOBS      -j* --jobs      'Number of parallel jobs' \
	NO_FILTER -m  --no-filter 'Do not filter probable false positives' \
	VERBOSE   -v  --verbose   'Verbose output'


	# Parse arguments
	while [ $# -gt 0 ]; do
		$options.getopt option "$1"
		case "$option" in
		PKG_* | CLEAN | DEVELOPER | NO_FILTER | VERBOSE)
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
			eval "$bsda_opts_split"
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

	if $flags.check PKG_QUIET -ne 0; then
		# Print package name/origin only, skip duplicates
		$($this.Term).filter 1 "/usr/bin/awk -F: '!a[\$0=\$1]++'"
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
	$($this.Term).stdout "usage: pkg_validate [-aCcDdghiOoqrvx] [-j jobs] [pkg-name]
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
			IFS=$'\n' $($this.Term).stderr "Checking packages:" \
			                               "------------------" \
			                               "$pkgs" \
			                               "------------------"
		fi
	fi

	log ${this}packages= "$pkgs"
}

#
# Fork off missing library checks and collect results.
#
pkg:validate:Session.run() {
	local IFS term maxjobs pkgs fifo flags
	local jobs jobpids fmt count num pkg

	# Initialise dispatcher
	IFS=$'\n'

	$this.Term term
	$this.getJobs maxjobs
	$this.getPackages pkgs
	$this.Fifo fifo
	$this.Flags flags

	#
	# Dispatch jobs
	#
	jobs=0  # Number of running jobs
	log ${this}jobpids=
	while [ $((jobs += 1)) -le $((maxjobs)) ]; do
		# Dispatch job
		$this.job &
		log ${this}jobpids.push_back $!
	done
	log jobpids=cat ${this}jobpids

	if $flags.check CLEAN -ne 0; then
		$flags.check PKG_ORIGIN -eq 0 && fmt="%n-%v" || fmt="%o"
		$fifo.sink $'pkg:query:select "${fmt}\034%Fs\034%Fp" ${pkgs}'
	else
		# Total number of packages/jobs
		log pkgs.count num
		count=0 # Completed packages
		fmt="Checking package %${#num}d of $num: %s"
		while kill -0 $jobpids 2>&- && log pkgs.pop_front pkg; do
			# Perform parallel job dispatch and terminal output
			: $((count+=1))
			$term.line 0 "$(printf "$fmt" $count "$pkg")" | \
			$fifo.sink $'pkg:query:select "${pkg}\034%Fs\034%Fp" ${pkg}'
		done
	fi
	if ! kill -0 $jobpids 2>&-; then
		$term.stderr "${0##*/}: ERROR: worker process died unexpectedly"
		return 1
	fi
	# Soft harvest jobs, i.e. let them complete
	for pid in $jobpids; do
		$fifo.send exit
	done
	wait $jobpids
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
pkg:validate:Session:validate() {
	local sum hash msg
	sum=
	hash=
	msg=
	case "$2" in
	1\$*)
		hash=sha256
	;;
	esac
	if [ -z "$hash" -o ! -x "/sbin/$hash" ]; then
		msg="unsupported $hash checksum for $3"
	elif [ -L "$3" ]; then
		local link fmt
		# symlink
		link="$(/usr/bin/readlink -n "$3")"
		# Pkgng removes the leading /, and appends
		# a 0 byte. The latter was originally by
		# accident, but will forever remain in order
		# to not break existing packages.
		fmt="%s"
		if [ -z "${link##/*}" ]; then
			fmt="%s\\0"
		fi
		sum="$(printf "$fmt" "${link#/}" | /sbin/$hash -q 2>&1)"
		if [ "$sum" != "${2#*\$}" ]; then
			msg="checksum mismatch for $3"
		elif [ ! -e "$3" ]; then
			if $flags.check DEVELOPER -ne 0; then
				msg="cannot follow symlink $3 to ${link}"
			fi
		fi
	elif [ ! -r "$3" ]; then
		# file cannot be read, follow the path until something
		# checks true for existence and recheck
		local path file
		path="$3"
		while [ -n "$path" -a ! -e "$path" ]; do
			path="${path%/*}"
		done
		if [ ! -r "$path" ]; then
			# file or location not accessible
			if $flags.check NO_FILTER -ne 0; then
				file="${3#${path}}"
				msg="user ${USER} cannot access ${path}${file:+(${file})}"
			fi
		else
			msg="missing file $3"
		fi
	else
		# regular file hash
		sum="$(/sbin/$hash -q "$3" 2>&1)"
		if [ "$sum" != "${2#*\$}" ]; then
			msg="checksum mismatch for $3"
		fi
	fi
	if [ -n "${msg}" ]; then
		$term.stdout "$1: ${msg}"
	fi
}

#
# Check the sha256 sum of a whole batch of files.
#
# Refers mismatching files to pkg:validate:Session:validate() for
# individual treatment.
#
# @param *
#	A set of tuples: '%s\034%s\034%s' pkg chksum path
# @param term
#	A bsda:tty:Async instance
# @param flags
#	A bsda:opts:Flags instance
#
pkg:validate:Session:batch() {
	local IFS files hash
	IFS=$'\n\034'
	# batch hash all files
	files="$(echo "$*" | /usr/bin/sed $'s/.*\034//')"
	# compare hashes
	for file in ${files}; do # redirect symlinks
		test -L "${file}" && echo "/dev/null" || echo "${file}"
	done | /usr/bin/xargs /sbin/sha256 -q 2>&1 | while read -r hash; do
		# on sha256 mismatch validate the file
		if [ -n "${1##*\$"${hash}"$'\034'*}" ]; then
			$class:validate $1
		fi
		shift
	done
}

#
# Read the requested number of lines from stdin and output on stdout.
#
# Exits early if a line reads `exit`, the exit line is omitted from the
# output.
#
# @param 1
#	The number of lines to read
# @retval 0
#	The requested number of lines was read
# @retval 1
#	The `exit` string was read before reaching the requested number
#	of lines
#
pkg:validate:Session:read() {
	local line i
	line=
	i=0
	while read -r line; do
		if [ "${line}" = exit ]; then
			return 1
		fi
		echo "$line"
		if [ $((i += 1)) -ge $(($1)) ]; then
			return 0
		fi
	done
}

#
# Check files in a package for missing libraries.
#
# Reads jobs from the FIFO and performs them. Accepts the following
# inputs:
#
# - '%s\034%s\034%s' pkg chksum path
# - 'exit'
#
pkg:validate:Session.job() {
	local flags term fifo IFS lines
	$this.Flags flags
	$this.Term term
	$this.Fifo fifo
	IFS=$'\n'
	while lines="$($fifo.source $class:read 64)"; do
		$class:batch $lines
	done
	$class:batch $lines
	return 0
}
