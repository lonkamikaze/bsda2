test -n "$_pkg_libchk_" && return 0
readonly _pkg_libchk_=1

. ${bsda_dir:-.}/bsda_async.sh
. ${bsda_dir:-.}/bsda_tty.sh
. ${bsda_dir:-.}/bsda_fifo.sh
. ${bsda_dir:-.}/bsda_util.sh
. ${bsda_dir:-.}/pkg_options.sh
. ${bsda_dir:-.}/pkg_info.sh

#
# Create an asynchronous Terminal class.
#
bsda:async:createClass bsda:tty:Async bsda:tty:Terminal

#
# A simple class to pass job results through the FIFO.
#
# The misses attribute is a list in the format:
#	binary FS info FS tag
#
# `FS` is the ASCII Field Separator character `\034`.
#
# The binary is the path of the inspected executable or library,
# the info field carries the relevant information depending on the
# tag, one of:
#
# - miss
# - compat
# - verbose
# - invalid
#
# Secondary tags may occor appended with a comma:
#
# - direct
# - indirect
# - os/abi
#
# The ldd_filter.awk script documents which info is carried for which
# tag.
#
bsda:obj:createClass pkg:libchk:JobResult \
	r:pkg    "The package name" \
	r:misses "The list of missed packages" \
	r:sline  "The status line id this job is listed on" \
	i:init   "Constructor"

#
# A job result constructor.
#
# @param 1
#	The package name
# @param 2
#	The list of missed libraries
# @param 3
#	The status line number
#
pkg:libchk:JobResult.init() {
	setvar ${this}pkg "$1"
	setvar ${this}misses "$2"
	setvar ${this}sline "$3"
}

#
# The session class for pkg_libchk.
#
bsda:obj:createClass pkg:libchk:Session \
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
# Constructor for a pkg_libchk session.
#
# @param @
#	The command line arguments
#
pkg:libchk:Session.init() {
	# Setup terminal manager
	bsda:tty:Async ${this}Term

	# Set defaults
	setvar ${this}jobs $(($(/sbin/sysctl -n hw.ncpu 2>&- || echo 1) + 1))

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
pkg:libchk:Session.params() {
	local options flags option

	bsda:opts:Options options
	$caller.delete $options
	pkg:options:append $options
	$options.append \
	CLEAN     -c  --clean     'Turn off progress output' \
	HELP      -h  --help      'Display the list of command arguments' \
	JOBS      -j* --jobs      'Number of parallel jobs' \
	NO_FILTER -m  --no-filter 'Do not perform false positive filtering' \
	NO_COMPAT -n  --no-compat 'Do not report compat dependencies' \
	VERBOSE   -v  --verbose   'Verbose output'

	$this.Flags flags

	while [ $# -gt 0 ]; do
		$options.getopt option "$1"
		case "$option" in
		PKG_* | CLEAN | NO_FILTER | NO_COMPAT | VERBOSE)
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

	if $flags.check CLEAN; then
		$($this.Term).deactivate
	fi

	if $flags.check VERBOSE && $flags.check PKG_QUIET; then
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
pkg:libchk:Session.help() {
	local usage
	$1.usage usage "\t%.2s, %-18s  %s\n"
	$($this.Term).stdout "usage: pkg_libchk [-aCcdghimnOoqrvx] [-j jobs] [pkg-name]
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
pkg:libchk:Session.packages() {
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
# Splits the given arguments to the fields `file`, `lib` and `tags`.
#
IFS=$'\034' bsda:util:mapfun pkg:libchk:Session:mapmiss file lib tags

#
# Print a serialised JobResult instances.
#
# @param &1
#	The status line id used for this job
# @param 2
#	The serialised JobResult
#
pkg:libchk:Session.print() {
	local res misses pkg IFS miss file lib tags output flags indirect osabi
	bsda:obj:deserialise res "$2"
	$caller.setvar "$1" "$($res.getSline)"

	$this.Flags flags

	$res.getPkg pkg
	$res.getMisses misses
	$res.delete

	test -z "$misses" && return

	# Honour quiet output flag
	if $flags.check PKG_QUIET; then
		$($this.Term).stdout "$pkg"
		return $?
	fi

	# Give a detailed account of every file missing a library
	IFS=$'\n'
	log output=
	for miss in $misses; {
		$class:mapmiss "$miss"
		# check for secondary tags
		osabi=
		indirect=
		case "${tags}" in *,os/abi*)   osabi="Unbranded ELF file ";; esac
		case "${tags}" in *,indirect*) indirect="indirectly ";;      esac
		# print for primary tags
		case "${tags}" in
		miss*)
			log output.push_back "$pkg: ${osabi}$file ${indirect}misses $lib";;
		compat*)
			log output.push_back "$pkg: ${osabi}$file ${indirect}uses $lib";;
		verbose*)
			log output.push_back "$pkg: $file: $lib";;
		invalid*)
			log output.push_back "$pkg: ldd(1): $lib";;
		*)      # should not be reached
			log output.push_back "$pkg: $file ??? $lib";;
		esac
	}
	$($this.Term).stdout "$output"
}

#
# Fork off missing library checks and collect results.
#
pkg:libchk:Session.run() {
	local IFS pkg pkgs result maxjobs jobs sline term fmt count num fifo

	# Initialise dispatcher
	IFS=$'\n'

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
			$fifo.recv result
			jobs=$((jobs - 1))
			$this.print sline "$result"
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
		$fifo.recv result
		$this.print sline "$result"
		$term.line $sline
		jobs=$((jobs - 1))
		count=$((count + 1))
		$term.line 0 "$(printf "$fmt" $jobs)"
	done
}

#
# Static function for ldd(1) output processing.
#
# Refer to the ldd_filter.awk script to learn more about this function.
#
# @param 1
#	A boolean value indicating whether the use of compat libraries
#	should be tagged (1) or discarded (0)
# @param 2
#	A boolean value indicating whether output should be verbose (1)
#	or just output direct dependency errors (0)
# @param 3
#	A boolean value indicating that false positives should be filtered
#	from the output.
#
pkg:libchk:Session.ldd_filter() {
	/usr/bin/awk -f ${bsda_dir:-.}/ldd_filter.awk \
	             -vOFS=$'\034' -vCOMPAT="$1" -vVERBOSE="$2" -vFILTER="$3"
}

#
# Check files in a package for missing libraries.
#
# @param 1
#	The package to check
# @param 2
#	The status line this job is listed on
#
pkg:libchk:Session.job() {
	local IFS files misses res flags compat verbose filter
	IFS=$'\n'
	$this.Flags flags
	$flags.check NO_COMPAT -eq 0 && compat=1  || compat=0
	$flags.check VERBOSE   -ne 0 && verbose=1 || verbose=0
	$flags.check NO_FILTER -eq 0 && filter=1  || filter=0

	# The files of the package
	files="$(pkg:info:files $1)"

	# Get misses
	misses="$(printf '%s\0' $files \
	          | /usr/bin/xargs -0 /usr/bin/ldd 2>&1 \
	          | $class.ldd_filter "${compat}" "${verbose}" "${filter}")"

	# Check whether a miss is actually contained in the same
	# package, e.g. libjvm.so in openjdk
	if [ "$filter" -eq 1 ] && [ -n "$misses" ]; then
		misses="$( (echo "${files}"; echo "${misses}") | /usr/bin/awk '
			BEGIN { FS = SUBSEP }
			# blacklist package files
			NF == 1 {
				FILES[$0] # with path for compat
				sub(/.*\//, "")
				FILES[$0] # without path for miss
			}
			# print non-blacklisted misses
			NF > 1 && !($2 in FILES)
		')"
	fi

	# Create a JobResult, serialise it and send it back to the dispatcher
	pkg:libchk:JobResult res "$1" "$misses" "$2"
	$($this.Fifo).sink $res.serialise
}
