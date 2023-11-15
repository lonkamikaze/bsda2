#!/bin/sh

. install.inc

for file in $files; {
	source="${file%%,*}"
	test -z "${source}" && continue
	mode="${file%,*}"
	mode="${mode#*,}"
	file="${file##*,}"
	target="${destdir}${file#${destdir:+/}}"
	echo "installing: $target"
	mkdir -p "${target%/*}"
	eval "$replace_cmd '$source'" > "${target%.gz}"
	test "${target%.gz}" != "$target" && gzip -f9 "${target%.gz}"
	chmod "$mode" "$target"
}
