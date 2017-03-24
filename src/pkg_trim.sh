test -n "$_pkg_trim_" && return 0
readonly _pkg_trim_=1

. ${bsda_dir:-.}/bsda_dialog.sh
. ${bsda_dir:-.}/pkg_query.sh
. ${bsda_dir:-.}/bsda_opts.sh

#
# A dialog(1) driven script to get rid of unwanted leaf packages.
#

#
# Provides states for package selection to facilitate undo and redo.
#
# This is a two-way linked list, managed by StateManager.
#
# The only methods it offers are allShow(), allFlipped() and allChecked(),
# each of which return the accumulated values from this state back
# to the first state.
#
bsda:obj:createClass pkg:trim:State \
	a:private:next=pkg:trim:State \
	r:public:next       "Link to the next state" \
	r:public:prev       "Link to the previous state" \
	r:public:show       "The packages to show for selection" \
	r:public:flipped    "The packages that changed state" \
	r:public:checked    "The checked packages" \
	r:private:all       "Helper function to accumulate attributes" \
	x:public:allShow    "Return all shown packages up to this state" \
	x:public:allFlipped "Return all flipped packages up to this state" \
	x:public:allChecked "Return all checked packages up to this state"

#
# A helper function that provides an accumulated value.
#
# This function iterates from this state to the first state and accumulates
# the given attribute.
#
# @param &1
#	The variable to return the value to
# @param 2
#	The name of the state attribute to accumulate
#
pkg:trim:State.all() {
	local IFS state result val
	IFS=$'\n'
	result=
	state=$this
	while [ -n "$state" ]; do
		eval "val=\"\$${state}$2\""
		result="$val${val:+${result:+$IFS}}$result"
		$state.getPrev state
	done
	$caller.setvar "$1" "$result"
}

#
# Accumulates all shown packages from this state back to the first
# state.
#
# @param &1
#	The variable to return the accumulated packages to
#
pkg:trim:State.allShow() {
	$class.all "$1" show
}

#
# Accumulates all flipped packages from this state back to the first
# state.
#
# @param &1
#	The variable to return the accumulated packages to
#
pkg:trim:State.allFlipped() {
	$class.all "$1" flipped
}

#
# Accumulates all checked packages from this state back to the first
# state.
#
# @param &1
#	The variable to return the accumulated packages to
#
pkg:trim:State.allChecked() {
	$class.all "$1" checked
}

#
# Manages states and provides access to the accumulated state.
#
# It provides the following functionality:
#
# - It encapsulates use of pkg:query:* and avoids redundant access
#   by caching
# - It allows tracking of progress through isComplete() and isFirst()
# - It provides data for interactive use with checklist() and review()
# - It provides commit() to apply user selection to the current state
# - It provides prev() and next() to perform undo, redo and progress
#   to subsequently freed up packages
# - It provides the flipped(), checked() and unchecked() methods to
#   acquire the accumulated state
#
bsda:obj:createClass pkg:trim:StateManager \
	a:private:States=pkg:trim:State \
	r:private:pkgcached "A list of cached packages" \
	r:private:pkgcache  "A cache with all queried pkg information" \
	r:private:state     "The current state" \
	r:private:fmt       "The format string" \
	x:private:cache     "Updates information in the cache" \
	i:private:init      "Initialiase first state with leaf packages" \
	x:public:isComplete "Returns whether selection process is complete" \
	x:public:isFirst    "Returns whether this is the first state" \
	x:public:checklist  "Returns tuples for dialog(1) --checklist" \
	x:public:review     "Returns tuples for dialog(1) --menu" \
	x:public:commit     "Commits checked packages to the current state" \
	x:public:next       "Generates the next state" \
	x:public:prev       "Return to the previous state" \
	x:public:flipped    "All the packages changed" \
	x:public:checked    "All the packages checked" \
	x:public:unchecked  "All the packages changed to unchecked"

#
# Adds new packages to the package cache.
#
# The actual package cache is in the pkgcache attribute and contains
# tuples with the package, comment and autoremove flag separated
# by the pipe '|' character. Each tuple is on its own line.
#
# The pkgcached attribute is a newline separated list of the cached
# packages.
#
# Cached packages always resemble the system state of the packages,
# so cached packages are not changed and never requeried from the
# system.
#
pkg:trim:StateManager.cache() {
	# Get the packages that need to be in the cache
	local state show
	$this.getState state
	$state.getShow show
	if [ -z "$show" ]; then
		# No packages, that means nothing needs to be cached
		return 0
	fi

	# Determine which packages are not cached
	local IFS cached uncached
	IFS=$'\n'
	$this.getPkgcached cached
	uncached="$(echo "$show" | /usr/bin/grep -vFx "$cached")"
	if [ -z "$uncached" ]; then
		# All packages are cached
		return 0
	fi

	# Query packages and append to the cache
	local fmt pkgs cache
	$this.getFmt fmt
	$this.getPkgcache cache
	pkgs="$(pkg:query:select "$fmt|%c|%a" $uncached)"
	setvar ${this}pkgcache "$cache${cache:+${pkgs:+$IFS}}$pkgs"
	setvar ${this}pkgcached "$cached${cached:+${uncached:+$IFS}}$uncached"
}

#
# Initialise state manager.
#
# Initialises the first state to show all leaf packages.
#
# @param 1
#	The format string for a package identifier, defaults to "%n-%v"
#
pkg:trim:StateManager.init() {
	local fmt state
	fmt="${1:-%n-%v}"
	setvar ${this}fmt "$fmt"
	pkg:trim:State state
	setvar ${this}States $state
	setvar ${this}state $state
	# Initialise first state
	setvar ${state}show "$(pkg:query:leaves "$fmt")"
}

#
# Determines if package collection is complete.
#
# This depends on whether the current state has any packages left
# to display.
#
# @retval 0
#	Package selection is complete
# @retval 1
#	Package selection is not complete
#
pkg:trim:StateManager.isComplete() {
	local state show
	$this.getState state
	$state.getShow show
	test -z "$show"
}

#
# Determines if this is the first state.
#
# If this is the case, prev() may not be called.
#
# @retval 0
#	The current state is the first in the list
# @retval 1
#	The current state is not the first in the list
#
pkg:trim:StateManager.isFirst() {
	local first state
	$this.States first
	$this.getState state
	test $first = $state
}

#
# A static function used to repack IFS delimited arguments.
#
# This function packs all arguments into a pipe '|' delimited string,
# output on stdout.
#
# @param @
#	The arguments to pack
#
pkg:trim:StateManager._join() {
	local IFS
	IFS='|'
	echo "$*"
}

#
# A static filter converting cached packages to checklist format.
#
# Expects the contents of the cache on its standard input.
#
# @param 1
#	All packages to show
# @param 2
#	All the packages that should show a different state from
#	the cached state
#
pkg:trim:StateManager.checklist_filter() {
	/usr/bin/awk -F\| -vSHOW="$($class._join $1)" \
	                  -vFLIP="$($class._join $2)" '
	BEGIN {
		cnt = split(SHOW, a)
		for (i = 1; i <= cnt; ++i) {
			ASHOW[a[i]]
		}
		cnt = split(FLIP, a)
		for (i = 1; i <= cnt; ++i) {
			AFLIP[a[i]]
		}
	}
	$1 in AFLIP {$3 = !$3}
	$1 in ASHOW {print($1 "\n" $2 "\n" ($3 ? "on" : "off"))}'
}

#
# Produce dialog(1) --checklist style tuples with packages.
#
# This outputs all the packages the current state is supposed to
# show.
#
# @param &1
#	The variable to return the tuples to, the items are newline
#	separated
#
pkg:trim:StateManager.checklist() {
	# Put all packages into cache
	$this.cache

	local state show cache flipped tuples
	$this.getState state
	$state.getShow show
	$state.getFlipped flipped
	$this.getPkgcache cache
	tuples="$(echo "$cache" | /usr/bin/sort -t\| -k1 \
	          | $class.checklist_filter "$show" "$flipped")"
	$caller.setvar "$1" "$tuples"
}

#
# A static filter converting cached packages to menu format.
#
# Expects the contents of the cache on its standard input.
#
# @param 1
#	All checked packages
# @param 2
#	All packages changed to unchecked
#
pkg:trim:StateManager.review_filter() {
	/usr/bin/awk -F\| -vCHECK="$($class._join $1)" \
	                  -vUNCHECK="$($class._join $2)" '
	BEGIN {
		cnt = split(CHECK, a)
		for (i = 1; i <= cnt; ++i) {
			ACHECK[a[i]]
		}
		cnt = split(UNCHECK, a)
		for (i = 1; i <= cnt; ++i) {
			AUNCHECK[a[i]]
		}
	}
	$1 in ACHECK {print(" [*] " $1 "\n" $2)}
	$1 in AUNCHECK {print(" [ ] " $1 "\n" $2)}'
}

#
# Produce dialog(1) --menu style tuples with packages for selection
# review.
#
# This produces the accumulated checked packages and the changed
# packages.
#
# @param &1
#	The variable to return the tuples to, the items are newline
#	separated
#
pkg:trim:StateManager.review() {
	local checked unchecked cache tuples
	$this.checked checked
	$this.unchecked unchecked
	$this.getPkgcache cache
	tuples="$(echo "$cache" | /usr/bin/sort -t\| -k1 \
	          | $class.review_filter "$checked" "$unchecked")"
	$caller.setvar "$1" "$tuples"
}

#
# A static filter converting cached packages to a list of packages
# that have changed their state.
#
# Expects the contents of the cache on its standard input.
#
# @param 1
#	The list of packages that was displayed
# @param 2
#	The list of packages that was checked
#
pkg:trim:StateManager.commit_filter() {
	/usr/bin/awk -F\| -vSHOW="$($class._join $1)" \
	                  -vCHECK="$($class._join $2)" '
	BEGIN {
		cnt = split(SHOW, a)
		for (i = 1; i <= cnt; ++i) {
			ASHOW[a[i]]
		}
		cnt = split(CHECK, a)
		for (i = 1; i <= cnt; ++i) {
			ACHECK[a[i]]
		}
	}
	($1 in ASHOW) && (!$3 == ($1 in ACHECK)) {print $1}'
}

#
# Commits the checked packages to the current state.
#
# This removes the tail of states if any changes were made to the
# current one.
#
# @param 1
#	The checked packages for this state
#
pkg:trim:StateManager.commit() {
	# Check for redo
	local state next checked
	$this.getState state
	$state.getNext next
	if [ -n "$next" ]; then
		# This state already has a follower
		$state.getChecked checked
		if [ "$checked" == "$1" ]; then
			# No changes, reuse the next state
			return 0
		fi
		# Clean up tail that is no longer consistent with
		# this state
		$next.delete
		unset ${state}next next
	fi

	# Determine packages that do not have the cached state
	local show cache flipped
	$state.getShow show
	$this.getPkgcache cache
	flipped="$(echo "$cache" | $class.commit_filter "$show" "$1")"

	# Update the current state
	setvar ${state}flipped "$flipped"
	setvar ${state}checked "$1"
}

#
# Move to the next state.
#
# In case a next state already exists it is used. This may happen
# if the current state was reached via prev(), but no changes were
# made.
#
pkg:trim:StateManager.next() {
	# Move forward if no changes have been committed
	local state next
	$this.getState state
	$state.getNext next
	if [ -n "$next" ]; then
		setvar ${this}state $next
		return 0
	fi

	# Create and move to the next state
	pkg:trim:State next
	setvar ${next}prev $state
	setvar ${state}next $next
	setvar ${this}state $next

	# Initialise next state
	local fmt shown checked
	$this.getFmt fmt
	$state.allShow shown
	$state.allChecked checked
	setvar ${next}show "$(pkg:query:required_only_by "$fmt" $checked \
	                      | /usr/bin/grep -vFx "$shown")"
}

#
# Move to the previous state.
#
pkg:trim:StateManager.prev() {
	local state
	$this.getState state
	$state.getPrev ${this}state
}

#
# Returns the changed packages accumulated up to the current state.
#
# @param &1
#	The variable to return the packages to
#
pkg:trim:StateManager.flipped() {
	local state flipped
	$this.getState state
	$state.allFlipped flipped
	$caller.setvar "$1" "$flipped"
}

#
# Returns the checked packages accumulated up to the current state.
#
# @param &1
#	The variable to return the packages to
#
pkg:trim:StateManager.checked() {
	local state checked
	$this.getState state
	$state.allChecked checked
	$caller.setvar "$1" "$checked"
}

#
# Returns the packages changed to unchecked accumulated up to the
# current state.
#
# @param &1
#	The variable to return the packages to
#
pkg:trim:StateManager.unchecked() {
	local state checked flipped unchecked
	$this.getState state
	$state.allChecked checked
	$state.allFlipped flipped
	unchecked="$(echo "$flipped" | /usr/bin/grep -vFx "$checked")"
	$caller.setvar "$1" "$unchecked"
}

#
# The session class for pkg_trim.
#
bsda:obj:createClass pkg:trim:Session \
	a:private:Flags=bsda:opts:Flags \
	i:private:init      "The constructor" \
	x:private:help      "Print usage and exit" \
	x:private:params    "Handle command line arguments" \
	x:private:runReview "Review package selection" \
	x:private:run       "Perform package selection and processing"

#
# The session constructor.
#
# @param @
#	The command line arguments
#
pkg:trim:Session.init() {
	bsda:opts:Flags ${this}Flags

	$this.params "$@"
	$this.run
}

#
# Print usage and exit.
#
# @param 1
#	A reference to a bsda:opts:Options instance
#
pkg:trim:Session.help() {
	local usage
	$1.usage usage "\t%.2s, %-8s  %s\n"
	echo "usage: pkg_trim [-hoy]
$(echo -n "$usage" | /usr/bin/sort -f)"
	exit 0
}

#
# Process command line arguments.
#
# @param @
#	The command line arguments
#
pkg:trim:Session.params() {
	local options flags
	$this.Flags flags

	bsda:opts:Options options \
	HELP        -h --help   'Display the list of command arguments' \
	PKG_ORIGIN  -o --origin 'Show package origins instead of names' \
	PKG_YES     -y --yes    'Assume yes when asked to delete/autoremove'
	$caller.delete $options

	while [ $# -gt 0 ]; do
		$options.getopt option "$1"
		case "$option" in
		HELP)
			$this.help "$options"
		;;
		OPT_UNKNOWN | OPT_NOOPT)
			echo "Unknown parameter \"$1\"." 1>&2
			exit 1
		;;
		OPT_SPLIT)
			local arg
			arg="$1"
			shift
			set -- "${arg%${arg#-?}}" "-${arg#-?}" "$@"
			continue
		;;
		*)
			# Catch all the flags
			$flags.add "$option"
		;;
		esac
		shift
	done
}

#
# Opens a review dialog that lets the user look at all the affected
# packages.
#
# @param 1
#	The StateManager instance
# @param 2
#	The Dialog instance
#
pkg:trim:Session.runReview() {
	local tuples dummy ret
	$2.setArgs --extra-button --extra-label Back
	$1.review tuples
	if [ -z "$tuples" ]; then
		$2.msgbox dummy "You have neither selected nor unchecked any packages."
	else
		$2.menu dummy "Confirm package selection" $tuples
	fi
	ret=$?
	case $ret in
	0) # OK
	;;
	3) # Back
		$1.prev
	;;
	*) # Cancel/ESC
		return $ret
	;;
	esac
}

#
# Perform package selection and processing.
#
# The following process is performed:
#
# 1. Package selection
# 2. Ask what to do, delete or mark for autoremove
# 3. Perform delete or mark for autoremove
#
# @return
#	May return any unhandled failure of dialog(1)
#
pkg:trim:Session.run() {
	local IFS flags ret fmt dialog
	IFS=$'\n'
	$this.Flags flags

	# Use name-version packages unless PKG_ORIGIN is set
	fmt="%n-%v"
	$flags.check PKG_ORIGIN -ne 0 && fmt="%o"

	# Setup the dialog
	bsda:dialog:Dialog dialog
	$caller.delete $dialog

	#
	# Stage 1) Package Selection
	#

	local state text tuples
	pkg:trim:StateManager state "$fmt"
	$caller.delete $state
	while ! $state.isComplete; do
		if $state.isFirst; then
			text="Select leaf packages to remove"
			$dialog.setArgs
		else
			text="Select additional packages to remove"
			$dialog.setArgs --extra-button --extra-label Back
		fi
		# Call dialog checklist
		$state.checklist tuples
		$dialog.checklist checked "$text" $tuples
		ret=$?
		$state.commit "$checked"
		case $ret in
		0) # OK
			# Proceed to new packages
			$state.next
			if $state.isComplete; then
				$this.runReview "$state" "$dialog" || return $?
			fi
			;;
		3) # Back
			# Rollback
			$state.prev
			;;
		*) # Cancel/ESC
			return $ret
		esac
	done

	#
	# Stage 2) Processing
	#

	local flipped checked unchecked
	$state.flipped flipped
	$state.checked checked
	$state.unchecked unchecked

	# Nothing to do, leave
	if [ -z "$checked$unchecked" ]; then
		return 0
	fi

	# Select action
	local action enlist yes
	$dialog.setArgs --hline "This your last opportunity to Cancel!"
	$dialog.menu action "Perform the following action" \
	             Autoremove "Mark selected packages for 'pkg autoremove'" \
	             Delete     "Perform 'pkg delete' with selected packages" \
	|| return $?
	# Perform action
	yes=
	$flags.check PKG_YES -ne 0 && yes=-y
	# Always remove autoremove flag from unchecked packages
	if [ -n "$unchecked" ]; then
		/usr/sbin/pkg set $yes -A0 $unchecked || return $?
	fi
	# Delete or set autoremove flag
	case "$action" in
	Autoremove)
		# Only want changed packages
		checked="$(echo "$flipped" | /usr/bin/grep -Fx "$checked")"
		if [ -n "$checked" ]; then
			/usr/sbin/pkg set $yes -A1 $checked || return $?
		fi
	;;
	Delete)
		if [ -n "$checked" ]; then
			/usr/sbin/pkg delete $yes $checked || return $?
		fi
	;;
	esac
}
