test -n "$_pkg_libchk_" && return 0
readonly _pkg_libchk_=1

. ${bsda_dir:-.}/bsda_tty.sh
. ${bsda_dir:-.}/bsda_fifo.sh
. ${bsda_dir:-.}/pkg_options.sh
. ${bsda_dir:-.}/pkg_info.sh

#
# A simple object to pass job results through the FIFO.
#
# The misses attribute is a list in the format:
#	file "|" library "|" ("[direct]" | "[indirect]")
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
# The session object for pkg_libchk.
#
bsda:obj:createClass pkg:libchk:Session \
	r:private:flags    "A bsda:opts:Flags flag store and counter" \
	r:private:term     "The bsda:tty:Async instances for output" \
	r:private:fifo     "A bsda:fifo:Fifo instance" \
	r:private:packages "The list of packages to process" \
	r:private:jobs     "The number of parallel jobs" \
	i:public:init      "The constructor" \
	c:public:clean     "The destructor" \
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
	bsda:tty:Async ${this}term

	# Set defaults
	setvar ${this}jobs $(($(/sbin/sysctl -n hw.ncpu 2> /dev/null || echo 1) + 1))

	# Read command line arguments
	bsda:opts:Flags ${this}flags
	$this.params "$@"

	# Setup terminal lines
	$($this.getTerm).use $(($($this.getJobs) + 1))

	# Create the fifo
	bsda:fifo:Fifo ${this}fifo

	# Perform checks
	$this.run
}

#
# The destructor, clean up acquired resources.
#
pkg:libchk:Session.clean() {
	$($this.getFlags).delete
	$($this.getFifo).delete
	$($this.getTerm).delete
}

#
# Parse command line arguments.
#
# @param @
#	The command line arguments
#
pkg:libchk:Session.params() {
	local options flags nl option

	bsda:opts:Options options
	pkg:options:append $options
	$options.append \
	CLEAN     -c  --clean     'Turn off progress output' \
	HELP      -h  --help      'Display the list of commands' \
	JOBS      -j* --jobs      'Number of parallel jobs' \
	NO_FILTER -m  --no-filter 'Do not perform false positive filtering' \
	NO_COMPAT -n  --no-compat 'Do not report compat dependencies' \
	VERBOSE   -v  --verbose   'Verbose output' \

	$this.getFlags flags

	nl='
'

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
			if ! [ "$jobs" -eq "$jobs" ] 2> /dev/null; then
				$($this.getTerm).stderr \
					"The -j option must be followed by a number."
				exit 4
			elif [ "$jobs" -lt 1 ]; then
				$($this.getTerm).stderr \
					"The -j option must specify at least 1 job."
				exit 4
			else
				setvar ${this}jobs $jobs
			fi
		;;
		OPT_UNKNOWN)
			$($this.getTerm).stderr \
				"Unknown parameter \"$1\"."
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
		$($this.getTerm).deactivate
	fi

	if $flags.check VERBOSE -ne 0 && $flags.check PKG_QUIET -ne 0; then
		$($this.getTerm).stderr \
			"The parameters -v and -q may not be used at the same time."
		exit 3
	fi

	# Use the remaining arguments to query for packages
	$this.packages "$@"

	$options.delete
}

#
# Print usage message.
#
pkg:libchk:Session.help() {
	local usage
	$1.usage usage "\t%.2s, %-18s  %s\n"
	$($this.getTerm).stdout "usage: pkg_libchk [-aCcdghimnOoqrvx] [-j jobs] [pkg-name]
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
	local pkginfo flags pkgs
	$this.getFlags flags
	pkg:info:Env pkginfo $flags

	# Call pkg-info to acquire a list of packages
	if ! $pkginfo.match pkgs "$@"; then
		local errmsg errnum
		$pkginfo.getErrmsg errmsg
		$pkginfo.getErrnum errnum
		$($this.getTerm).stderr "$errmsg"
		exit $errnum
	fi

	$pkginfo.delete

	# Verbose output
	if $flags.check VERBOSE -ne 0; then
		if $flags.check PKG_ALL -ne 0; then
			$($this.getTerm).stderr "Checking all packages ..."
		else
			$($this.getTerm).stderr "Checking packages:" \
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
pkg:libchk:Session.print() {
	local res misses pkg IFS miss file lib output flags
	bsda:obj:deserialise res "$2"
	$caller.setvar "$1" "$($res.getSline)"

	$this.getFlags flags

	$res.getPkg pkg
	$res.getMisses misses
	$res.delete

	# Discard indirect dependencies
	if $flags.check VERBOSE -eq 0 && $flags.check NO_FILTER -eq 0; then
		misses="$(echo "$misses" | /usr/bin/grep -F '|[direct]')"
	fi

	test -z "$misses" && return

	# Honour quiet output flag
	if $flags.check PKG_QUIET -ne 0; then
		$($this.getTerm).stdout "$pkg"
		return
	fi

	# Give a detailed account of every file missing a library
	IFS='
'
	output=
	for miss in $misses; {
		file="${miss%%|*}"
		lib="${miss#*|}";lib="${lib%%|*}"
		if $flags.check VERBOSE -eq 0; then
			output="${output:+$output$IFS}$pkg: $file misses $lib"
		else
			if [ -z "${miss##*|\[direct]}" ]; then
				output="${output:+$output$IFS}$pkg: $file directly misses $lib"
			else
				output="${output:+$output$IFS}$pkg: $file indirectly misses $lib"
			fi
		fi
	}
	$($this.getTerm).stdout "$output"
}

#
# Fork off missing library checks and collect results.
#
pkg:libchk:Session.run() {
	local IFS pkg pkgs result maxjobs jobs term fmt count num fifo

	# Initialise dispatcher
	IFS='
'

	$this.getTerm term
	$this.getJobs maxjobs
	$this.getPackages pkgs
	$this.getFifo fifo
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

	# Terminate async terminal
	$term.deactivate
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
	local IFS file files lib misses miss res pfiles flags
	local compat
	IFS='
'
	$this.getFlags flags
	$flags.check NO_COMPAT -eq 0 && compat=1 || compat=

	# The files of the package
	files="$(pkg:info:files $1)"

	# Get misses
	misses="$(/usr/bin/ldd $files 2> /dev/null | /usr/bin/awk "
		/^[^ ].*:\$/{sub(/:\$/,\"\");file=\$0}
		/not found/${compat:+||/\/lib\/compat\//}{print file \"|\" \$1 \"|\"}
	")"

	# Check whether a miss is actually contained in the same
	# package, e.g. libjvm.so in openjdk
	if $flags.check NO_FILTER -eq 0 && [ -n "$misses" ]; then
		pfiles="$(echo "$files" \
		          | /usr/bin/sed -e 's,.*/,|,' -e 's,$,|,')"
		misses="$(echo "$misses" | /usr/bin/grep -vF "$pfiles")"
	fi

	# Verify misses
	messages=
	for miss in $misses; {
		file="${miss%%|*}"
		lib="${miss#*|}";lib="${lib%%|*}"

		# Direct dependency?
		if /usr/bin/readelf -d "$file" \
		   | /usr/bin/grep -qF "Shared library: [$lib]"; then
		   	miss="$miss[direct]"
		else
		   	miss="$miss[indirect]"
		fi

		messages="${messages:+$messages$IFS}$miss"
	}
	# Create a JobResult, serialise it and send it back to the dispatcher
	pkg:libchk:JobResult res "$1" "$messages" "$2"
	$($this.getFifo).sink $res.serialise
}

