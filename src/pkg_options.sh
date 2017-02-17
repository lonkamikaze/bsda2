test -n "$_pkg_options_" && return 0
readonly _pkg_options_=1

. ${bsda_dir:-.}/bsda_opts.sh

#
# Appends pkg-info(8) like options to a bsda:opts:Options instance.
#
# @param 1
#	The options to append to
#
pkg:options:append() { $1.append \
PKG_ALL              -a --all              'Select all packages' \
PKG_CASE_SENSITIVE   -C --case-sensitive   'Make pkg-name matching case sensitive' \
PKG_GLOB             -g --glob             'Treat pkg-name as a shell glob pattern' \
PKG_CASE_INSENSITIVE -i --case-insensitive 'Make pkg-name matching case insensitive' \
PKG_REGEX            -x --regex            'Treat pkg-name as a regular expression' \
PKG_DEPENDENCIES     -d --dependencies     'Select the packages on which pkg-name depends' \
PKG_REQUIRED_BY      -r --required-by      'Select the packages which require pkg-name' \
PKG_BY_ORIGIN        -O --by-origin        'Select by pkg-name origin' \
PKG_QUIET            -q --quiet            'Print only the requested information' \
PKG_ORIGIN           -o --origin           'Display package origins instead of names'
}
