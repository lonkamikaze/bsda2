set -f

files="
src/bprintf,0755,%%PREFIX%%/bin/bprintf
man/bprintf.1,0644,%%MAN%%/man1/bprintf.1.gz
src/bsda_async.sh,0644,%%DATADIR%%/bsda_async.sh
src/bsda_bsdmake.sh,0644,%%DATADIR%%/bsda_bsdmake.sh
src/bsda_container.sh,0644,%%DATADIR%%/bsda_container.sh
src/bsda_dialog.sh,0644,%%DATADIR%%/bsda_dialog.sh
src/bsda_elf.sh,0644,%%DATADIR%%/bsda_elf.sh
src/bsda_err.sh,0644,%%DATADIR%%/bsda_err.sh
ref/bsda_err.md,0644,%%DOCSDIR%%/ref/bsda_err.md
src/bsda_fifo.sh,0644,%%DATADIR%%/bsda_fifo.sh
src/bsda_fmt.sh,0644,%%DATADIR%%/bsda_fmt.sh
src/bsda_obj.sh,0644,%%DATADIR%%/bsda_obj.sh
ref/bsda_obj.md,0644,%%DOCSDIR%%/ref/bsda_obj.md
src/bsda_opts.sh,0644,%%DATADIR%%/bsda_opts.sh
src/bsda_tty.sh,0644,%%DATADIR%%/bsda_tty.sh
src/bsda_util.sh,0644,%%DATADIR%%/bsda_util.sh
src/buildflags.awk,0755,%%DATADIR%%/buildflags.awk
src/buildflags.conf.sample,0644,%%PREFIX%%/etc/buildflags.conf.sample
src/buildflags.mk,0644,%%DATADIR%%/buildflags.mk
man/buildflags.awk.1,0644,%%MAN%%/man1/buildflags.awk.1.gz
man/buildflags.conf.1,0644,%%MAN%%/man1/buildflags.conf.1.gz
man/buildflags.mk.1,0644,%%MAN%%/man1/buildflags.mk.1.gz
src/distviper,0755,%%PREFIX%%/sbin/distviper
man/distviper.8,0644,%%MAN%%/man8/distviper.8.gz
src/distviper.sh,0644,%%DATADIR%%/distviper.sh
src/interrupt.mk,0644,%%DATADIR%%/interrupt.mk
src/loaderupdate,0755,%%PREFIX%%/sbin/loaderupdate
src/loaderupdate.sh,0644,%%DATADIR%%/loaderupdate.sh
man/loaderupdate.8,0644,%%MAN%%/man8/loaderupdate.8.gz
src/makeplist,0755,%%PREFIX%%/sbin/makeplist
man/makeplist.8,0644,%%MAN%%/man8/makeplist.8.gz
src/makeplist_filter.awk,0755,%%DATADIR%%/makeplist_filter.awk
src/makeplist_keywords.awk,0755,%%DATADIR%%/makeplist_keywords.awk
src/makeplist.sh,0644,%%DATADIR%%/makeplist.sh
src/options.mk,0644,%%DATADIR%%/options.mk
src/pkg_info.sh,0644,%%DATADIR%%/pkg_info.sh
src/pkg_libchk,0755,%%PREFIX%%/sbin/pkg_libchk
man/pkg_libchk.1,0644,%%MAN%%/man1/pkg_libchk.1.gz
src/pkg_libchk.sh,0644,%%DATADIR%%/pkg_libchk.sh
src/pkg_options.sh,0644,%%DATADIR%%/pkg_options.sh
src/pkg_query.sh,0644,%%DATADIR%%/pkg_query.sh
src/pkg_trim,0755,%%PREFIX%%/sbin/pkg_trim
man/pkg_trim.8,0644,%%MAN%%/man8/pkg_trim.8.gz
src/pkg_trim.sh,0644,%%DATADIR%%/pkg_trim.sh
src/pkg_validate,0755,%%PREFIX%%/sbin/pkg_validate
man/pkg_validate.1,0644,%%MAN%%/man1/pkg_validate.1.gz
src/pkg_validate.sh,0644,%%DATADIR%%/pkg_validate.sh
src/type.sh,0644,%%DATADIR%%/type.sh
ref/type.md,0644,%%DOCSDIR%%/ref/type.md
LICENSE.md,0644,%%DOCSDIR%%/LICENSE.md
README.md,0644,%%DOCSDIR%%/README.md
"

IFS=$'\n'

for parameter in "$@"; {
	case "${parameter%%=*}" in
	-destdir | -prefix | -datadir | -docsdir | -tmp | -ports)
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
: ${ports=/usr/ports}

# If set, destdir should end with a /
destdir=${destdir:+${destdir%/}/}

replace="
%%PREFIX%%,$prefix
%%DATADIR%%,$datadir
%%DOCSDIR%%,$docsdir
%%MAN%%,$prefix/man
%%TMP%%,$tmp
%%PORTS%%,$ports
"

replace_cmd="sed -e '/#HACK/,/#hack/d'"

for substitution in $replace; {
	test -z "$substitution" && continue
	replace_cmd="$replace_cmd -e 's,$substitution,g'"
}

files="$(echo "$files" | eval "$replace_cmd")"
