test -n "$_pkg_version_" && return 0
readonly _pkg_version_=1

. ${bsda_dir:-.}/bsda_async.sh
. ${bsda_dir:-.}/bsda_tty.sh
. ${bsda_dir:-.}/bsda_fifo.sh
. ${bsda_dir:-.}/bsda_util.sh
. ${bsda_dir:-.}/pkg_options.sh
. ${bsda_dir:-.}/pkg_info.sh

#
# Define error codes.
#
bsda:err:createECs E_ARGS

#
# Create an asynchronous Terminal class.
#
bsda:async:createClass bsda:tty:Async bsda:tty:Terminal

#
# The session class for pkg_version.
#
bsda:obj:createClass pkg:version:Session \
	a:private:Flags=bsda:opts:Flags \
	a:private:Term=bsda:tty:Async \
	a:private:Fifo=bsda:fifo:Fifo \
	r:private:packages "The list of packages to process" \
	r:private:jobs     "The number of parallel jobs" \
	r:private:args     "A record of additional pkg-version arguments" \
	i:private:init     "The constructor" \
	x:private:params   "Parse command line arguments" \
	x:private:help     "Print usage message" \
	x:private:packages "Determine requested packages" \
	x:private:run      "Fork version checks" \
	x:private:runSync  "Perform checks in a single pkg-version call" \
	x:private:print    "Print a serialised JobResult instance" \
	x:private:job      "Perform version checks"

#
# Constructor for a pkg_version session.
#
# @param @
#	The command line arguments
#
pkg:version:Session.init() {
	# Setup terminal manager
	bsda:tty:Async ${this}Term

	# Set defaults
	setvar ${this}jobs $(/sbin/sysctl -n hw.ncpu 2>&- || echo 1)

	# Read command line arguments
	bsda:opts:Flags ${this}Flags
	$this.params "$@"

	# Setup terminal status lines
	$($this.Term).use $(($($this.getJobs) + 1))
	# Filter duplicates from stdout and stderr
	$($this.Term).filter 1 "/usr/bin/awk '!a[\$0]++'"
	$($this.Term).filter 2 "/usr/bin/awk '!a[\$0]++'"

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
pkg:version:Session.params() {
	local options flags option cnt args

	bsda:opts:Options options
	$caller.delete $options
	pkg:options:append $options
	$options.append \
	CLEAN          -c  --clean           'Turn off progress output' \
	HELP           -h  --help            'Display the list of command arguments' \
	INDEX          -I* --index           'Use index file to determine if package is out of date' \
	JOBS           -j* --jobs            'Number of parallel jobs' \
	LIKE           -l* --like            'Display only packages with the given version status' \
	NOT_LIKE       -L* --not-like        'Display only packages unlike the given version status' \
	PORTS          -P  --ports           'Use ports to determine if a package is out of date' \
	REMOTE         -R  --remote          'Use repository catalogue to determine if a package is out of date' \
	NO_REPO_UPDATE -U  --no-repo-update  'Disable repository auto update' \
	VERBOSE        -v  --verbose         'Verbose output'

	$this.Flags flags

	while [ $# -gt 0 ]; do
		$options.getopt option "$1"
		$flags.add "$option"
		case "$option" in
		PKG_* | CLEAN)
		;;
		HELP)
			$this.help "$options"
		;;
		INDEX)
			local index
			index="${1#-I}"
			index="${index#--index}"
			if [ -z "$index" ]; then
				index="$2"
				shift
			fi
			if ! [ -z "${index}" -o -r "${index}" ]; then
				bsda:err:raise E_ARGS "The -I parameter must be followed by a readable file or left empty."
			fi
			rec ${this}args.push_back "-I${index}"
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
				bsda:err:raise E_ARGS "The -j parameter must be followed by a number."
			elif [ "$jobs" -lt 1 ]; then
				bsda:err:raise E_ARGS "The -j parameter must specify at least 1 job."
			else
				setvar ${this}jobs $jobs
			fi
		;;
		LIKE)
			local like
			like="${1#-l}"
			like="${like#--like}"
			if [ -z "$like" ]; then
				like="$2"
				shift
			fi
			rec ${this}args.push_back "-l${like}"
		;;
		NO_REPO_UPDATE)
			rec ${this}args.push_back -U
		;;
		NOT_LIKE)
			local unlike
			unlike="${1#-L}"
			unlike="${unlike#--not-like}"
			if [ -z "$unlike" ]; then
				unlike="$2"
				shift
			fi
			rec ${this}args.push_back "-L${unlike}"
		;;
		PORTS)
			rec ${this}args.push_back -P
		;;
		REMOTE)
			rec ${this}args.push_back -R
		;;
		VERBOSE)
			rec ${this}args.push_back -v
		;;
		OPT_UNKNOWN)
			bsda:err:raise E_ARGS "Unknown parameter \"$1\"."
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
		bsda:err:raise E_ARGS "The -v and -q parameters are mutually exclusive."
	fi

	if $flags.check PKG_QUIET; then
		rec ${this}args.push_back -q
	fi

	if $flags.check LIKE -gt 1; then
		bsda:err:raise E_ARGS "The -l parameter may only be used once."
	fi

	if $flags.check NOT_LIKE -gt 1; then
		bsda:err:raise E_ARGS "The -L parameter may only be used once."
	fi

	if $flags.check LIKE && $flags.check NOT_LIKE; then
		bsda:err:raise E_ARGS "The -l and -L parameters are mutually exclusive."
	fi

	# Count mutually exclusive -I, -P and -R parameters
	cnt=0
	$flags.check INDEX  && : $((cnt += 1))
	$flags.check PORTS  && : $((cnt += 1))
	$flags.check REMOTE && : $((cnt += 1))
	if [ ${cnt} -gt 1 ]; then
		bsda:err:raise E_ARGS "The -I [index], -P and -R parameters are mutually exclusive."
	fi

	# Use the remaining arguments to query for packages
	$this.packages "$@"
}

#
# Print usage message.
#
pkg:version:Session.help() {
	local usage
	$1.usage usage "\t%.2s, %-18s  %s\n"
	$($this.Term).stdout "usage: pkg_version [-aCcdghiOoPqrRvx] [-I [index]] [-j jobs] [-l limchar] [-L limchar] [pkg-name ...]
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
pkg:version:Session.packages() {
	local pkginfo flags pkgs warn
	$this.Flags flags
	pkg:info:Env pkginfo $flags
	$caller.delete $pkginfo

	# Call pkg-info to acquire a list of packages
	if ! $pkginfo.match pkgs "$@"; then
		local errmsg errnum
		$pkginfo.getErrmsg errmsg
		$pkginfo.getErrnum errnum
		bsda:err:raise $errnum "$errmsg"
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
# Fork off package version checks and collect results.
#
pkg:version:Session.run() {
	local IFS pkg pkgs maxjobs jobs sline term fmt count num fifo
	local stat ret

	# Initialise dispatcher
	unset IFS
	ret=0

	$this.Term term
	$this.getJobs maxjobs
	$this.getPackages pkgs
	$this.Fifo fifo
	log pkgs.count num
	        # Total number of packages/jobs
	count=0 # Completed jobs
	jobs=0  # Number of running jobs
	sline=1 # The next status line to use

	#
	# Dispatch jobs
	#
	fmt="Jobs done: %${#num}d of $num"
	$term.line 0 "$(printf "$fmt" $count)"
	while log pkgs.pop_front pkg; do
		# Wait for jobs to complete
		if [ $jobs -ge $maxjobs ]; then
			# Blocking read
			$fifo.recv sline stat
			ret=$((stat > ret ? stat : ret))
			jobs=$((jobs - 1))
			count=$((count + 1))
		fi
		# Dispatch job
		(
			bsda:obj:fork
			$term.line 0 "$(printf "$fmt" $count)"
			$term.line $sline "$pkg"
			$this.job "$pkg" $sline
		) &
		jobs=$((jobs + 1))
		sline=$((sline + 1))
	done

	#
	# Wait for last jobs
	#
	fmt="Waiting for %${#maxjobs}d job(s)"
	while [ $jobs -gt 0 ]; do
		# Blocking read
		$fifo.recv sline stat
		ret=$((stat > ret ? stat : ret))
		$term.line $sline
		jobs=$((jobs - 1))
		count=$((count + 1))
		$term.line 0 "$(printf "$fmt" $jobs)"
	done

	return $ret
}

#
# Check files in a package for missing libraries.
#
# @param 1
#	The package to check
# @param 2
#	The status line this job is listed on
#
pkg:version:Session.job() {
	local err
	err="$( (
		$this.getArgs args
		$this.Flags flags
		rec args.set_ifs
		out="$(/usr/sbin/pkg version ${args} "-e${1}" | \
		       /usr/bin/sed -E '$s/^[^ ]* *//')"
		ret=$?
		if [ -n "${out}" ]; then
			# Vanilla print everything but the last line (WARNINGS etc.)
			if [ -z "${out##*$'\n'*}" ]; then
				$term.stdout "${out%$'\n'*}"
			fi
			# Print the last line (version check result)
			if $flags.check LIKE && $flags.check PKG_QUIET; then
				$term.stdout "${1}"
			else
				$term.stdout "$(printf "%-34s %s\n" "$1" "${out##*$'\n'}")"
			fi
		fi
		$fifo.send "$2 $ret"
	) 2>&1 )"
	${err:+$term.stderr} ${err:+"${err}"}
}
