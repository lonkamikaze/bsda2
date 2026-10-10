test -n "$_pkg_validate_" && return 0
readonly _pkg_validate_=1

. ${bsda_dir:-.}/bsda_async.sh
. ${bsda_dir:-.}/bsda_tty.sh
. ${bsda_dir:-.}/bsda_fifo.sh
. ${bsda_dir:-.}/pkg_options.sh
. ${bsda_dir:-.}/pkg_info.sh
. ${bsda_dir:-.}/pkg_query.sh

bsda:err:createECs E_PKG_VALIDATE_WHICH

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
	r:private:packages   "The list of packages to process" \
	r:private:jobs       "The number of parallel jobs" \
	r:private:batch      "The number of files to check in one batch" \
	r:private:jobpids    "The active job pids" \
	r:private:sha256cmd  "The sha256 command" \
	r:private:blake2bcmd "The b2sum command for blake2b hashes" \
	r:private:blake2scmd "The b2sum command for blake2s hashes" \
	i:private:init       "The constructor" \
	c:private:clean      "The destructor" \
	x:private:params     "Parse command line arguments" \
	x:private:help       "Print usage message" \
	x:private:packages   "Determine requested packages" \
	x:private:run        "Fork file checks" \
	x:private:job        "Perform file checks"

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
	setvar ${this}batch 512

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
		kill $pids 2> /dev/null
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
	BATCH     -b* --batch     'The number of files to check in one batch' \
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
		BATCH)
			local batch
			batch="${1#-b}"
			batch="${batch#--batch}"
			if [ -z "${batch}" ]; then
				batch="$2"
				shift
			fi
			if ! type:match uint "${batch}"; then
				$($this.Term).stderr \
					"The -b option must be followed by a positive integer."
				exit 5
			elif ! [ ${batch} -gt 0 -a ${batch} -le 65536 ]; then
				$($this.Term).stderr \
					"The -b option must be in the range [1; 65536]."
				exit 5
			else
				setvar ${this}batch "${batch}"
			fi
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

	if $flags.check CLEAN; then
		$($this.Term).deactivate
	fi

	if $flags.check VERBOSE && $flags.check PKG_QUIET; then
		$($this.Term).stderr \
			"The parameters -v and -q may not be used at the same time."
		exit 3
	fi

	if $flags.check PKG_QUIET; then
		# Print package name/origin only, skip duplicates
		$($this.Term).filter 1 "/usr/bin/awk -F: '!a[\$0=\$1]++'"
	fi

	# Check for hash algorithm binaries
	for bin in sha256 b2sum; do
		if ! /usr/bin/which -s "${bin}"; then
			bsda:err:raise E_PKG_VALIDATE_WHICH "ERROR: cannot locate ${bin} executable"
		fi
	done
	setvar ${this}sha256cmd "$(/usr/bin/which sha256)"
	setvar ${this}blake2bcmd "$(/usr/bin/which b2sum) -a blake2b"
	setvar ${this}blake2scmd "$(/usr/bin/which b2sum) -a blake2s"

	# Use the remaining arguments to query for packages
	$this.packages "$@"
}

#
# Print usage message.
#
pkg:validate:Session.help() {
	local usage
	$1.usage usage "\t%.2s, %-18s  %s\n"
	$($this.Term).stdout "usage: pkg_validate [-aCcDdghiOoqrvx] [-b batchsize] [-j jobs] [pkg-name]
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

	# Extra verbose output
	if $flags.check VERBOSE -gt 1; then
		if $flags.check PKG_ALL; then
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

	if $flags.check CLEAN; then
		$flags.check PKG_ORIGIN -eq 0 && fmt="%n-%v" || fmt="%o"
		$fifo.sink $'pkg:query:select -e "%?F!=0" "${fmt}\034%Fs\034%Fp" ${pkgs}'
	else
		# Total number of packages/jobs
		log pkgs.count num
		count=0 # Completed packages
		fmt="Checking package %${#num}d of $num: %s"
		while kill -0 $jobpids 2>&- && log pkgs.pop_front pkg; do
			# Perform parallel job dispatch and terminal output
			: $((count+=1))
			$term.line 0 "$(printf "$fmt" $count "$pkg")" | \
			$fifo.sink $'pkg:query:select -e "%?F!=0" "${pkg}\034%Fs\034%Fp" ${pkg}'
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
	local IFS sum cmd bin msg dev
	IFS=$'\n '
	sum=
	cmd=
	msg=
	case "$2" in
	1\$*)
		$this.getSha256cmd cmd
		cmd="${cmd} -q"
	;;
	2\$????????????????????????????????????????????????????????????????)
		$this.getBlake2scmd cmd
	;;
	2\$????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????)
		$this.getBlake2bcmd cmd
	;;
	esac
	bin="${cmd%% *}"
	bin="${bin##*/}"
	$flags.check DEVELOPER && dev=1 || dev=
	if [ -z "${cmd}" ]; then
		msg="unsupported ${bin:+${bin} }checksum for $3: $2"
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
		sum="$(printf "$fmt" "${link#/}" | ${cmd} 2>&1)"
		sum="${sum%% *}"
		if [ "$sum" != "${2#*\$}" ]; then
			msg="${bin} checksum mismatch for $3"${dev:+$'\n'"expect: ${2#*\$}"$'\n'"found:  ${sum}"}
		elif [ ! -e "$3" ]; then
			if [ -n "${dev}" ]; then
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
			if $flags.check NO_FILTER; then
				file="${3#${path}}"
				msg="user ${USER} cannot access ${path}${file:+(${file})}"
			fi
		else
			msg="missing file $3"
		fi
	else
		# regular file hash
		sum="$(${cmd} "$3" 2>&1)"
		sum="${sum%% *}"
		if [ "$sum" != "${2#*\$}" ]; then
			msg="${bin} checksum mismatch for $3"${dev:+$'\n'"expect: ${2#*\$}"$'\n'"found:  ${sum}"}
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
pkg:validate:Session:batchV1() {
	local IFS cmd hashes miss tuple
	IFS=$'\n '
	# compare hashes
	$this.getSha256cmd cmd
	hashes="$(
		echo "$*"                    \
		| /usr/bin/cut -d$'\034' -f3 \
		| /usr/bin/xargs ${cmd} 2>&1 \
		| /usr/bin/awk -vOFS=$'\034' '{sub(/^\(/, "", $2); sub(/\)$/, "", $2); print("", "1$" $4, $2)}'
	)"
	IFS=$'\n'
	miss="$(echo "$*" | /usr/bin/grep -vF "${hashes}")"
	for tuple in ${miss}; do
		IFS=$'\n\034'
		$class:validate ${tuple}
	done
}

#
# Check the blake2b checksum of a whole batch of files.
#
# Blake2b checksums are generated by pkg tools compiled for 32 bit
# architectures.
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
pkg:validate:Session:batchV2b() {
	local IFS cmd hashes miss tuple
	IFS=$'\n '
	# compare hashes
	$this.getBlake2bcmd cmd
	hashes="$(
		echo "$*"                    \
		| /usr/bin/cut -d$'\034' -f3 \
		| /usr/bin/xargs ${cmd} 2>&1 \
		| /usr/bin/awk -vOFS=$'\034' '{print("", "2$" $1, $2)}'
	)"
	IFS=$'\n'
	miss="$(echo "$*" | grep -vF "${hashes}")"
	for tuple in ${miss}; do
		IFS=$'\n\034'
		$class:validate ${tuple}
	done
}

#
# Check the blake2s checksum of a whole batch of files.
#
# Blake2s checksums are generated by pkg tools compiled for 32 bit
# architectures.
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
pkg:validate:Session:batchV2s() {
	local IFS cmd hashes miss tuple
	IFS=$'\n '
	# compare hashes
	$this.getBlake2scmd cmd
	hashes="$(
		echo "$*"                    \
		| /usr/bin/cut -d$'\034' -f3 \
		| /usr/bin/xargs ${cmd} 2>&1 \
		| /usr/bin/awk -vOFS=$'\034' '{print("", "2$" $1, $2)}'
	)"
	IFS=$'\n'
	miss="$(echo "$*" | grep -vF "${hashes}")"
	for tuple in ${miss}; do
		IFS=$'\n\034'
		$class:validate ${tuple}
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
	i=$(($1))
	while [ $((i -= 1)) -ge 0 ] && read -r line; do
		if [ "${line}" = "exit" ]; then
			return 1
		fi
		echo "$line"
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
pkg:validate:Session.job() (
	bsda:obj:fork
	$this.Flags flags
	$this.Term term
	$this.Fifo fifo
	$this.getBatch batch
	IFS=$'\n'
	while :; do
		lines="$($fifo.source $class:read ${batch})"
		status="$?"
		linesV2="$(echo "${lines}" | /usr/bin/awk -F$'\034' -f "${bsda_dir}/pcv2_filter.awk")"
		linesV1="$(echo "${lines}" | /usr/bin/awk -F$'\034' '$2 !~ /^2\$/')"
		linesV2s="$(echo "${linesV2}" | /usr/bin/grep -E $'\034''2\$[0-9a-f]{64}'$'\034')"
		linesV2b="$(echo "${linesV2}" | /usr/bin/grep -vFx "${linesV2s}")"
		test -n "${linesV1}"  && $class:batchV1  ${linesV1}
		test -n "${linesV2b}" && $class:batchV2b ${linesV2b}
		test -n "${linesV2s}" && $class:batchV2s ${linesV2s}
		if [ "$((status))" -eq 1 ]; then
			return 0
		fi
	done
)
