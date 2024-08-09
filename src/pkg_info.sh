test -n "$_pkg_info_" && return 0
readonly _pkg_info_=1

. ${bsda_dir:-.}/bsda_obj.sh
. ${bsda_dir:-.}/pkg_query.sh

#
# This package collects ways to query pkg-info(8).
#
# The pkg:info:Env class can be used to make complex queries.
#
# Simple wrappers are provided as static functions:
#
# - pkg:info:files()
#

#
# An environment to make pkg-info(8) queries.
#
# An instance requires a bsda:opts:Flags instance, which can be used
# to configure the behaviour of the queried information.
#
# The flags used are defined in pkg_options.sh.
#
bsda:obj:createClass pkg:info:Env \
	r:private:flags "A reference to a bsda:opts:Flag instance" \
	r:public:errmsg "Holds an error message in case of failure" \
	r:public:errnum "The error number returned by pkg-info" \
	r:public:warn   "Warning messages from the last pkg-info call" \
	i:private:init  "The constructor" \
	x:public:match  "For the given query return a list of packages" \
	x:public:files  "For the given packages list all installed files"

#
# The constructor initialises the reference to the bsda:opts:Flags instance.
#
# @param 1
#	A pointer to a bsda:opts:Flags instances
#
pkg:info:Env.init() {
	setvar ${this}flags "$1"
}

#
# Take the list of requested packages and turn it into a list of package
# names.
#
# This method is affected by the given flags as described in
# pkg:options:append(). The PKG_ALL flag is set if no arguments have
# been given.
#
# The PKG_DEPENDENCIES and PKG_REQUIRED_BY flags select the given packages
# and their dependencies/requirements instead of just selecting the
# dependencies/requirements of the packages.
#
# @param &1
#	The variable to return the list of packages to
# @param @
#	The package queries
#
pkg:info:Env.match() {
	local IFS retvar flags args pkgs ret dep req
	IFS=$'\n'

	retvar="$1"
	shift
	$this.getFlags flags

	# Fall back to all packages if no queries are given
	if [ $# -eq 0 ] && $flags.check PKG_ALL -eq 0; then
		$flags.add PKG_ALL
	fi

	# Select command line arguments
	log args= -E
	if $flags.check PKG_ALL; then
		log args.push_back -aq
	fi
	if $flags.check PKG_CASE_SENSITIVE; then
		log args.push_back -C
	fi
	if $flags.check PKG_GLOB; then
		log args.push_back -g
	fi
	if $flags.check PKG_CASE_INSENSITIVE; then
		log args.push_back -i
	fi
	if $flags.check PKG_REGEX; then
		log args.push_back -x
	fi
	if $flags.check PKG_BY_ORIGIN; then
		log args.push_back -Oq
	fi

	# Get requested packages
	pkgs="$(/usr/sbin/pkg info $args "$@" 2>&1)"
	ret=$?
	# Bail on error.
	if [ $ret -ne 0 ]; then
		setvar ${this}errmsg "$pkgs"
		setvar ${this}errnum $ret
		return $ret
	fi
	# Remove and record warnings.
	if [ -n "$pkgs" ] && [ -z "${pkgs##*pkg: Warning:*}" ]; then
		setvar ${this}warn "$(echo "$pkgs" | /usr/bin/grep '^pkg: Warning:')"
		pkgs="$(echo "$pkgs" | /usr/bin/grep -v '^pkg: Warning:')"
	fi
	# Get related packages, unless all packages are selected any way
	if $flags.check PKG_ALL -eq 0; then
		# Get dependencies if requested
		if $flags.check PKG_DEPENDENCIES; then
			dep="$(/usr/sbin/pkg info -qd $pkgs 2>&-)"
			pkgs="$pkgs${dep:+$IFS}$dep"
			pkgs="$(echo "$pkgs" | /usr/bin/awk '!a[$0]++')"
		fi
		# Get required by packages if requested
		if $flags.check PKG_REQUIRED_BY; then
			req="$(/usr/sbin/pkg info -qr $pkgs 2>&-)"
			pkgs="$pkgs${req:+$IFS}$req"
			pkgs="$(echo "$pkgs" | /usr/bin/awk '!a[$0]++')"
		fi
	fi

	# Sort packages by number of files in descending order, so
	# the longest running jobs are processed first. Number of
	# files is a better predictor of job execution time than package
	# size.
	pkgs="$(pkg:query:sort -rn '%#F' $pkgs)"

	# Origins are equally valid unique identifiers, so they can be
	# used internally as well, so we do not have to convert for
	# display.
	if $flags.check PKG_ORIGIN; then
		pkgs="$(pkg:query:origin $pkgs 2>&-)"
	fi

	# Return the collected packages
	$caller.setvar "$retvar" "$pkgs"
	return 0
}

#
# Puts the list of all files installed by the given packages on stdout.
#
# @param @
#	A list of packages
#
pkg:info:files() {
	/usr/sbin/pkg info -ql "$@" 2>&1
}

#
# Outputs the origins of the given packages.
#
# @param @
#	A list of packages
#
pkg:info:origins() {
	/usr/sbin/pkg info -qo "$@"
}
