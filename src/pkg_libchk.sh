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
# - miss,direct
# - compat,direct
# - miss
# - compat
# - verbose
# - invalid
#
# The `ldd_filter()` method documents which info is carried for which
# tag. An additional `direct` tag means the dependency is directly
# required for the given binary instead of being pulled in via another
# library.
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
	local res misses pkg IFS miss file lib tags output flags
	bsda:obj:deserialise res "$2"
	$caller.setvar "$1" "$($res.getSline)"

	$this.Flags flags

	$res.getPkg pkg
	$res.getMisses misses
	$res.delete

	# Discard indirect dependencies
	if $flags.check VERBOSE -eq 0 && $flags.check NO_FILTER -eq 0; then
		misses="$(echo "$misses" | /usr/bin/grep ',direct$')"
	fi

	test -z "$misses" && return

	# Honour quiet output flag
	if $flags.check PKG_QUIET -ne 0; then
		$($this.Term).stdout "$pkg"
		return $?
	fi

	# Give a detailed account of every file missing a library
	IFS=$'\n'
	output=
	for miss in $misses; {
		$class:mapmiss "$miss"
		case "${tags}" in
		miss,direct)
			output="${output}$pkg: $file misses $lib${IFS}";;
		compat,direct)
			output="${output}$pkg: $file uses $lib${IFS}";;
		miss)
			output="${output}$pkg: $file indirectly misses $lib${IFS}";;
		compat)
			output="${output}$pkg: $file indirectly uses $lib${IFS}";;
		verbose*)
			output="${output}$pkg: $file: $lib${IFS}";;
		invalid*)
			output="${output}$pkg: ldd(1): $lib${IFS}";;
		*)      # should not be reached
			output="${output}$pkg: $file ??? $lib${IFS}";;
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
			$fifo.recv result
			jobs=$((jobs - 1))
			$this.print sline "$result"
			count=$((count + 1))
		fi
		# Select next package to process
		pkg="${pkgs%%$IFS*}"
		# Dispatch job
		(
			bsda:obj:fork
			$term.line 0 "$(printf "$fmt" $count)"
			$term.line $sline "$pkg"
			$this.job "$pkg" $sline
		) &
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
# Expects ldd(1) output on stdin and performs the following processing
# steps:
#
# 1. Filter irrelevant lines
# 2. Format lines
# 3. Classify (i.e. tag) lines
#
# This exists, because `ldd -f` is unreliable
# [see](https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=259069).
# This is not the first time that pkg_libchk silently failed to detect
# missing libraries, because something about ldd changed.
#
# Input lines that indicate the given file is not a binary executable/library
# or that a dependency was successfully resolved are dismissed.
# The remaining lines are converted to the following fields separated
# by the ASCII Field Separator (FS) character:
#
# - binary:
#   The executable or library that was checked
# - info:
#   Usually a library name/path, see the table below
# - tag:
#   The type of information carried, see the table below
#
# The following tags exist:
#
# | Tag     | Binary | Info                | Description                    |
# |---------|--------|---------------------|--------------------------------|
# | compat  | yes    | dependency path     | Path matches `*/lib*/compat/*` |
# | miss    | yes    | dependency filename | Dependency was not found       |
# | verbose | yes    | error message       | Binary specific ldd(1) error   |
# | invalid | -      | whole input line    | Unknown ldd(1) output          |
#
# @param 1
#	A boolean value indicating whether the use of compat libraries
#	should be tagged (1) or discarded (0)
#
pkg:libchk:Session.ldd_filter() {
	/usr/bin/awk -vCOMPAT="$1" '
	# prints: binary name, info, tag
	function printrow(bin, info, tag) {
		# Output each row only once, at least on FreeBSD
		# stable/13-n247530-3637d2a1835e ldd(1) prints missing
		# dependencies many times.
		# This output filter changed the runtime for
		# `pkg_libck samba413` after a libicu update from
		# >120s to ~4s, supposedly because every reported
		# missing dependency corresponds to a readelf(1) call
		# and this package produces 23601 lines of output
		# without the filter.
		if (!ROW[bin, info, tag]++) {
			printf("%s" SUBSEP "%s" SUBSEP "%s\n", bin, info, tag)
		}
	}
	# update binary name
	/^[^\t].*:$/ {
		sub(/:$/, "")
		BIN=$0
		next
	}
	# compat library
	COMPAT && /^\t.* => .*\/lib[^\/]*\/compat\/.* \(0x[0-9a-f]+\)$/ {
		sub(/^\t.* => /, "")
		sub(/ \(0x[0-9a-f]+\)$/, "")
		printrow(BIN, $0, "compat")
		next
	}
	# ignore
	/^\t.* \(0x[0-9a-f]+\)$/                  || # library was found
	/^ldd: .*: not a dynamic ELF executable$/ || # non-executable
	/^ldd: .*: Invalid argument$/             || # non-executable
	/^.*: exit status 1$/                     {  # redundant message
		next
	}
	# missing library
	/\(0\)$/ {
		sub(/^\t/, "")
		sub(/ => .*/, "")
		printrow(BIN, $0, "miss")
		next
	}
	# verbose error
	/ldd: .*: .*/ {
		sub(/ldd: /, "")
		file=$0
		sub(/: [^:]*$/, "", file)
		sub(/.*: /, "")
		printrow(file, $0, "verbose")
		next
	}
	# unknown/invalid ldd output
	{
		printrow("", $0, "invalid")
	}'
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
	local IFS file files lib tags misses miss res flags compat
	IFS=$'\n'
	$this.Flags flags
	$flags.check NO_COMPAT -eq 0 && compat=1 || compat=0

	# The files of the package
	files="$(pkg:info:files $1)"

	# Get misses
	misses="$(printf '%s\0' $files \
	          | /usr/bin/xargs -0 /usr/bin/ldd 2>&1 \
	          | $class.ldd_filter "${compat}")"

	# Check whether a miss is actually contained in the same
	# package, e.g. libjvm.so in openjdk
	if $flags.check NO_FILTER -eq 0 && [ -n "$misses" ]; then
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

	# Tag direct dependencies
	messages=
	for miss in $misses; {
		$class:mapmiss "$miss"
		case "$tags" in miss | compat)
			lib="${lib##*/}"

			if /usr/bin/readelf -d "$file" \
			   | /usr/bin/grep -qF "Shared library: [$lib]"; then
				miss="$miss,direct"
			fi
			;;
		esac
		messages="${messages:+$messages$IFS}$miss"
	}
	# Create a JobResult, serialise it and send it back to the dispatcher
	pkg:libchk:JobResult res "$1" "$messages" "$2"
	$($this.Fifo).sink $res.serialise
}
