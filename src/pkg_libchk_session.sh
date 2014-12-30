#
# Copyright (c) 2014
# Dominic Fandrey <kamikaze@bsdforen.de>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# Include once.
test -n "$pkg_libchk_session" && return 0
readonly pkg_libchk_session=1

. ${bsda_dir:-.}/bsda_tty.sh
. ${bsda_dir:-.}/bsda_messaging.sh

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
	r:private:term         "The bsda:tty:Terminal instances for output" \
	r:private:fifo         "The file name for the FIFO" \
	r:private:listener     "The bsda:messaging:FifoListener instance" \
	r:private:sender       "The bsda:messaging:FifoSender instance" \
	r:private:packages     "The list of packages to process" \
	r:private:clean        "Clean output (no status) flag" \
	r:private:dependencies "Work on dependencies flag" \
	r:private:jobs         "The number of parallel jobs" \
	r:private:mean         "Flag to turn of false positive checks" \
	r:private:compat       "Consider compat libs missing flag" \
	r:private:origin       "Display origin instead of name flag" \
	r:private:raw          "Raw output flag" \
	r:private:requiredBy   "Work on requiring packages flag" \
	r:private:verbose      "Verbosity flag" \
	i:public:init          "The constructor" \
	c:public:clean         "The destructor" \
	x:private:params       "Parse command line arguments" \
	x:private:help         "Print usage message" \
	x:private:packages     "Determine requested packages" \
	x:private:run          "Fork library checks" \
	x:private:print        "Print a serialised JobResult instance" \
	x:private:job          "Perform library checks"

#
# Constructor for a pkg_libchk session.
#
# @param @
#	The command line arguments
#
pkg:libchk:Session.init() {
	# Setup terminal manager
	bsda:tty:Terminal ${this}term

	# Set defaults
	setvar ${this}fifo "$(/usr/bin/mktemp -ut libchk)"
	setvar ${this}jobs $(($(/sbin/sysctl -n hw.ncpu 2> /dev/null || echo 1) + 1))
	setvar ${this}compat 1

	# Read command line arguments
	$this.params "$@"

	# Setup terminal lines
	$($this.getTerm).use $(($($this.getJobs) + 1))

	# Create the fifo
	bsda:messaging:FifoListener ${this}listener $($this.getFifo)
	bsda:messaging:FifoSender   ${this}sender   $($this.getFifo)

	# Generate a list of packages
	$this.packages

	# Perform checks
	$this.run
}

#
# The destructor, clean up acquired resources.
#
pkg:libchk:Session.clean() {
	$($this.getListener).delete
	$($this.getSender).delete
	$($this.getTerm).delete
}

#
# Parse command line arguments.
#
# @param @
#	The command line arguments
#
pkg:libchk:Session.params() {
	local nl option

	nl='
'

	for option in "$@"; {
		case "$option" in
		-a | --all)
			setvar ${this}packages -qa
		;;
		-c | --clean)
			$($this.getTerm).deactivate
			setvar ${this}clean 1
		;;
		-d | --dependencies)
			setvar ${this}dependencies 1
		;;
		-h | --help)
			$this.help
		;;
		-j* | --jobs*)
			local jobs
			jobs="${option#-j}"
			jobs="${jobs#--jobs}"
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
		-m | --mean)
			setvar ${this}mean 1
		;;
		-n | --no-compat)
			setvar ${this}compat
		;;
		-o | --origin)
			setvar ${this}origin 1
		;;
		-q | --raw)
			setvar ${this}raw 1
			if [ -n "$($this.getVerbose)" ]; then
				$($this.getTerm).stderr \
					"The parameters -v and -q may not be used at the same time."
				exit 3
			fi
		;;
		-r | --required-by)
			setvar ${this}requiredBy 1
		;;
		-v | --verbose)
			setvar ${this}verbose 1
			if [ -n "$($this.getRaw)" ]; then
				$($this.getTerm).stderr \
					"The parameters -q and -v may not be used at the same time."
				exit 3
			fi
		;;
		-? | --*)
			$($this.getTerm).stderr \
				"Unknown parameter \"$option\"."
			exit 2
		;;
		-*)
			$this.params "${option%${option#-?}}"
			$this.params "-${option#-?}"
		;;
		*)
			local pkgs
			$this.getPackages pkgs
			setvar ${this}packages "$pkgs${pkgs:+$nl}$option"
		;;
		esac
	}
}

#
# Print usage message.
#
pkg:libchk:Session.help() {
	$($this.getTerm).stdout "$name v$version
usage:	$name [-a] [-c] [-d] [-h] [-jN] [-m] [-n] [-o] [-q] [-r] [-v] [packages]"
	exit 0
}

#
# Take the list of requested packages and turn it into a list of package
# names.
#
# The list of requested packages is created by the Session.param() method.
#
pkg:libchk:Session.packages() {
	local IFS pkgs dep req ret
	IFS='
'
	$this.getPackages pkgs
	test -z "$pkgs" && pkgs=-qa
	
	if pkgs="$(/usr/sbin/pkg info -E $pkgs 2>&1)"; then :; else
		ret=$?
		$($this.getTerm).stderr "$pkgs"
		exit $ret
	fi
	if [ -n "$($this.getDependencies)" ]; then
		dep="$(/usr/sbin/pkg info -qd $pkgs)"
		pkgs="$pkgs${dep:+$IFS}$dep"
	fi
	if [ -n "$($this.getRequiredBy)" ]; then
		req="$(/usr/sbin/pkg info -qr $pkgs)"
		pkgs="$pkgs${req:+$IFS}$req"
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
	local res misses verbose pkg IFS miss file lib output
	bsda:obj:deserialise res "$2"
	$caller.setvar "$1" "$($res.getSline)"

	$res.getMisses misses
	$this.getVerbose verbose
	$this.getMean mean

	# Discard indirect dependencies
	if [ -z "$verbose" -a -z "$($this.getMean)" ]; then
		misses="$(echo "$misses" | /usr/bin/grep -F '|[direct]')"
	fi

	test -z "$misses" && return
	$res.getPkg pkg

	# Honour package origin output flag
	if [ -n "$($this.getOrigin)" ]; then
		pkg="$(/usr/sbin/pkg info -qo "$pkg")"
	fi

	# Honour raw output flag
	if [ -n "$($this.getRaw)" ]; then
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
		if [ -z "$verbose" ]; then
			output="${output:+$output$IFS}$pkg: $file misses $lib"
		fi
		if [ -n "$verbose" ]; then
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
	local IFS pkg pkgs result lines maxjobs jobs term fmt count num

	# Initialise dispatcher
	IFS='
'

	$this.getTerm term
	$this.getJobs maxjobs
	$this.getPackages pkgs
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
		while [ $jobs -ge $maxjobs ]; do
			$($this.getListener).receiveLine result lines
			if [ $lines -gt 0 ]; then
				jobs=$((jobs - lines))
				$this.print sline "$result"
				count=$((count + lines))
				$term.line 0 "$(printf "$fmt" $count)"
				break # Do not waste time sleeping when
				      # a job slot is available
			fi
			/bin/sleep 0.1
		done
		# Select next package to process
		pkg="${pkgs%%$IFS*}"
		pkgs="${pkgs#$pkg}"
		pkgs="${pkgs#$IFS}"
		$term.line $sline "$pkg"
		# Dispatch job
		(
			bsda:obj:fork
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
		$($this.getListener).receiveLine result lines
		if [ $lines -gt 0 ]; then
			$this.print sline "$result"
			$term.line $sline " "
			jobs=$((jobs - lines))
			count=$((count + lines))
			$term.line 0 "$(printf "$fmt" $jobs)"
			continue
		fi
		/bin/sleep 0.1
	done
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
	local IFS file files lib misses miss res mean pfiles
	local compat
	IFS='
'
	files="$(/usr/sbin/pkg info -ql "$1")"
	        # The files of the package

	# Get misses
	$this.getCompat compat
	misses="$(/usr/bin/ldd $files 2> /dev/null | /usr/bin/awk "
		/^[^ ].*:\$/{sub(/:\$/,\"\");file=\$0}
		/not found/${compat:+||/\/lib\/compat\//}{print file \"|\" \$1 \"|\"}
	")"

	$this.getMean mean
	# Check whether a miss is actually contained in the same
	# package, e.g. libjvm.so in openjdk
	if [ -z "$mean" -a -n "$misses" ]; then
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
	$($this.getSender).send "$($res.serialise)"
}

