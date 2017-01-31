test -n "$_pkg_trim_" && return 0
readonly _pkg_trim_=1

. ${bsda_dir:-.}/bsda_dialog.sh
. ${bsda_dir:-.}/pkg_query.sh
. ${bsda_dir:-.}/bsda_container.sh
. ${bsda_dir:-.}/bsda_opts.sh

#
# A dialog(1) driven script to get rid of unwanted leaf packages.
#

#
# The session class for pkg_trim.
#
bsda:obj:createClass pkg:trim:Session \
	r:private:dialog "A bsda:dialog:Dialog instance" \
	r:private:flags  "A bsda:opts:Flags instance" \
	i:private:init   "The constructor" \
	c:private:clean  "The destructor" \
	x:private:help   "Print usage and exit" \
	x:private:params "Handle command line arguments" \
	x:private:run    "Perform package selection and processing"

#
# The session constructor.
#
# @param @
#	The command line arguments
#
pkg:trim:Session.init() {
	bsda:dialog:Dialog ${this}dialog || return
	bsda:opts:Flags ${this}flags

	$this.params "$@"
	$this.run
}

#
# The destructor for this session.
#
pkg:trim:Session.clean() {
	$($this.getFlags).delete
	$($this.getDialog).delete
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
	$this.getFlags flags

	bsda:opts:Options options \
	HELP        -h --help   'Display the list of command arguments' \
	PKG_ORIGIN  -o --origin 'Show package origins instead of names' \
	PKG_YES     -y --yes    'Assume yes when asked to delete/autoremove'

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
	$options.delete
}

#
# Static function called by pkg:trim:Session.run().
#
# This function makes changes within the context of the caller.
#
# @param showstack,checkedstack
#	Updated with the context of the last dialog call
# @param show,checked,shown,allchecked,undo
#	Setup for the next dialog call
# @param dialog,unlist,auto
#	Used by pkg:trim:Session.run_review()
# @return
#	May fail if the selection process is completed and
#	pkg:strim:Session.run_review() fails
#
pkg:trim:Session.run_proceed() {
	$showstack.push "$show"
	$checkedstack.push "$checked"
	shown="$shown$IFS$show"
	allchecked="$allchecked${checked:+$IFS$checked}"
	show="$(pkg:query:required_only_by "$fmt" $allchecked \
	        | /usr/bin/grep -vFx "$shown")"
	undo=
	if [ -z "$show" ]; then
		$class.run_review || return
	fi
}

#
# Static function called by pkg:trim:Session.run().
#
# This function makes changes within the context of the caller.
#
# @param showstack,checkedstack
#	Used to restore the context of the previous dialog call
# @param show,checked,shown,allchecked,undo
#	Restored to match the previous dialog call
#
pkg:trim:Session.run_rollback() {
	$showstack.pop show
	$checkedstack.pop checked
	shown="${shown%$IFS$show}"
	allchecked="${allchecked%$checked}"
	allchecked="${allchecked%$IFS}"
	undo=1
}

#
# Static function called by pkg:trim:Session.run_proceed().
#
# This function makes changes within the context of the caller.
#
# @param dialog
#	The bsda:dialog:Dialog instance to use
# @param unlist
#	Set to a list of packages that were unchecked even though
#	their autoremove flag is set
# @param shown,allchecked,auto
#	Used to setup unlist
# @param tuples
#	Used for display
# @param showstack,checkedstack,show,checked,undo
#	Used by pkg:trim:Session.run_rollback()
# @return
#	May return any unhandled failure of dialog(1)
#
pkg:trim:Session.run_review() {
	local selected
	$dialog.setArgs --extra-button --extra-label Back
	unlist="$(echo "$shown" | /usr/bin/grep -vFx "$allchecked" \
	          | /usr/bin/grep -Fx "$auto" )"
	tuples="$( (
		enlist="$(echo "$allchecked" | /usr/bin/sort)"
		test -n "$enlist" && pkg:query:select " [*]|$fmt|%c" $enlist
		test -n "$unlist" && pkg:query:select " [ ]|$fmt|%c" $unlist
	) | /usr/bin/sort -t\| -k2 | /usr/bin/sed "s/|/ /;s/|/\\$IFS/" )"
	if [ -z "$tuples" ]; then
		$dialog.msgbox selected "You have neither selected nor unchecked any packages."
	else
		$dialog.menu selected "Confirm package selection" $tuples
	fi
	ret=$?
	case $ret in
	0) # OK
	;;
	3) # Back
		$class.run_rollback || return
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
#    1. Start with a list of leaf packages
#    2. Show a dialog to select packages
#    3. Create a list of new leaf packages
#    4. Unless empty go back to 1.2.
#    5. Ask for confirmation of the selection
# 2. Ask what to do, delete or mark for autoremove
# 3. Perform delete or mark for autoremove
#
# @return
#	May return any unhandled failure of dialog(1)
#
pkg:trim:Session.run() {
	local IFS flags ret fmt dialog auto
	IFS='
'
	$this.getFlags flags

	# Use name-version packages unless PKG_ORIGIN is set
	fmt="%n-%v"
	$flags.check PKG_ORIGIN -ne 0 && fmt="%o"

	# Get the dialog
	$this.getDialog dialog
	# List of packages with their autoremove flag set
	readonly auto="$(pkg:query:auto "$fmt")"

	local show shown allchecked
	# Start with leaf packages
	show="$(pkg:query:leaves "$fmt")"
	shown=
	allchecked=

	# Select packages until no new leaves show up
	local undo unlist showstack checkedstack text checked count tuples
	undo=
	unlist=
	bsda:container:Array showstack
	bsda:container:Array checkedstack
	while [ -n "$show" ]; do
		# Generate dialog checklist tuples
		tuples="$( (
			if [ -z "$undo" ]; then
				# First time these packages are shown, use
				# the autoremove flag
				pkg:query:select "$fmt|%c|%a" $show \
				| /usr/bin/sed 's/|0$/|off/;s/|1$/|on/'
			else
				# Restore checked status from last run
				off="$(echo "$show" | /usr/bin/grep -vFx "$checked")"
				test -n "$checked" \
				&& pkg:query:select "$fmt|%c|on" $checked
				test -n "$off" \
				&& pkg:query:select "$fmt|%c|off" $off
			fi
		) | /usr/bin/sort | /usr/bin/sed "s/|/\\$IFS/g" )"
		# Configure dialog
		$showstack.getCount count
		if [ $((count)) -eq 0 ]; then
			text="Select leaf packages to remove"
			$dialog.setArgs
		else
			text="Select additional packages to remove"
			$dialog.setArgs --extra-button --extra-label Back
		fi
		# Call dialog checklist
		$dialog.checklist checked "$text" $tuples
		ret=$?
		case $ret in
		0) # OK
			# Proceed to new packages
			$class.run_proceed || return
			;;
		3) # Back
			# Rollback
			$class.run_rollback || return
			;;
		*) # Cancel/ESC
			return $ret
		esac
	done
	$showstack.delete
	$checkedstack.delete

	# Nothing to do, leave
	if [ -z "$allchecked" ] && [ -z "$unlist" ]; then
		return 0
	fi

	# Select action
	local action enlist yes
	$dialog.setArgs --hline "This your last opportunity to Cancel!"
	$dialog.menu action "Perform the following action" \
	             Autoremove "Mark selected packages for 'pkg autoremove'" \
	             Delete     "Perform 'pkg delete' with selected packages" \
	|| return
	# Perform action
	yes=
	$flags.check PKG_YES -ne 0 && yes=-y
	case "$action" in
	Autoremove)
		enlist="$(echo "$allchecked" | /usr/bin/grep -vFx "$auto" )"
		if [ -n "$unlist" ]; then
			/usr/sbin/pkg set $yes -A0 $unlist || return
		fi
		if [ -n "$enlist" ]; then
			/usr/sbin/pkg set $yes -A1 $enlist || return
		fi
	;;
	Delete)
		if [ -n "$unlist" ]; then
			/usr/sbin/pkg set $yes -A0 $unlist || return
		fi
		if [ -n "$allchecked" ]; then
			/usr/sbin/pkg delete $yes $allchecked || return
		fi
	;;
	esac
}
