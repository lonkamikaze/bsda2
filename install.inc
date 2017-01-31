files="
src/bsda_container.sh,0644,%%DATADIR%%/bsda_container.sh
src/bsda_dialog.sh,0644,%%DATADIR%%/bsda_dialog.sh
src/bsda_fifo.sh,0644,%%DATADIR%%/bsda_fifo.sh
src/bsda_obj.sh,0644,%%DATADIR%%/bsda_obj.sh
src/bsda_opts.sh,0644,%%DATADIR%%/bsda_opts.sh
src/bsda_tty.sh,0644,%%DATADIR%%/bsda_tty.sh
src/buildflags.awk,0755,%%DATADIR%%/buildflags.awk
src/buildflags.conf.sample,0644,%%PREFIX%%/etc/buildflags.conf.sample
src/buildflags.mk,0644,%%DATADIR%%/buildflags.mk
src/buildflags.awk.1,0644,%%MAN%%/man1/buildflags.awk.1.gz
src/buildflags.conf.1,0644,%%MAN%%/man1/buildflags.conf.1.gz
src/buildflags.mk.1,0644,%%MAN%%/man1/buildflags.mk.1.gz
src/distviper,0755,%%PREFIX%%/sbin/distviper
src/distviper.1,0644,%%MAN%%/man1/distviper.1.gz
src/distviper.sh,0644,%%DATADIR%%/distviper.sh
src/pkg_info.sh,0644,%%DATADIR%%/pkg_info.sh
src/pkg_libchk,0755,%%PREFIX%%/sbin/pkg_libchk
src/pkg_libchk.1,0644,%%MAN%%/man1/pkg_libchk.1.gz
src/pkg_libchk.sh,0644,%%DATADIR%%/pkg_libchk.sh
src/pkg_options.sh,0644,%%DATADIR%%/pkg_options.sh
src/pkg_query.sh,0644,%%DATADIR%%/pkg_query.sh
src/pkg_trim,0755,%%PREFIX%%/sbin/pkg_trim
src/pkg_trim.8,0644,%%MAN%%/man8/pkg_trim.8.gz
src/pkg_trim.sh,0644,%%DATADIR%%/pkg_trim.sh
bsda_obj.md,0644,%%DOCSDIR%%/bsda_obj.md
LICENSE.md,0644,%%DOCSDIR%%/LICENSE.md
README.md,0644,%%DOCSDIR%%/README.md
"

IFS='
'

for parameter in "$@"; {
	case "${parameter%%=*}" in
	-destdir | -prefix | -datadir | -docsdir | -tmp)
		value="${parameter#*=}"
		parameter="${parameter%%=*}"
		parameter="${parameter#-}"
		eval "$parameter='$value'"
		;;
	-nodoc)
		files="$(echo "$files" | grep -vF "%%MAN%%${IFS}%%DOCSDIR%%")"
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
: ${docsdir=$prefix/share/doc/bsda2}
: ${tmp=/tmp}

# If set, destdir should end with a /
destdir=${destdir:+${destdir%/}/}

replace="
%%PREFIX%%,$prefix
%%DATADIR%%,$datadir
%%DOCSDIR%%,$docsdir
%%MAN%%,$prefix/man
%%TMP%%,$tmp
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
