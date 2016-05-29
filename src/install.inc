files="
bsda_messaging.sh,0644,%%DATADIR%%/bsda_messaging.sh
bsda_obj.sh,0644,%%DATADIR%%/bsda_obj.sh
bsda_tty.sh,0644,%%DATADIR%%/bsda_tty.sh
head.awk,0755,%%DATADIR%%/head.awk
pkg_libchk,0755,%%PREFIX%%/sbin/pkg_libchk
pkg_libchk.1,0644,%%MAN%%/man1/pkg_libchk.1.gz
pkg_libchk_session.sh,0644,%%DATADIR%%/pkg_libchk_session.sh
"

for parameter; {
	case "${parameter%%=*}" in
	-destdir | -prefix | -datadir)
		value="${parameter#*=}"
		parameter="${parameter%%=*}"
		parameter="${parameter#-}"
		eval "$parameter='$value'"
		;;
	-nodoc)
		files="$(echo "$files" | grep -v '%%MAN%%')"
		;;
	*)
		echo "Unknown parameter '$parameter'." 1>&2
		return 1
		;;
	esac
}

: ${destdir=}
: ${prefix=/usr/local}
: ${datadir=$prefix/share/bsda2}

# If set, destdir should end with a /
destdir=${destdir%/}${destdir:+/}

replace="
%%PREFIX%%,$prefix
%%DATADIR%%,$datadir
%%MAN%%,$prefix/man
"

replace_cmd="sed -e '/#HACK/,/#hack/d'"

IFS='
'

argsel() {
	i="$1"
	shift
	eval "echo \"\$$i\""
}

for substitution in $replace; {
	test -z "$substitution" && continue
	replace_cmd="$replace_cmd -e 's,$substitution,g'"
	for i in $(jot 9); do
		select="${substitution%%,*}"
		replace="${substitution#*,}"
		replace_cmd="$replace_cmd -e 's,${select%\%\%}:$i%%,$(eval argsel $i $replace),g'"
	done
}

files="$(echo "$files" | eval "$replace_cmd")"

