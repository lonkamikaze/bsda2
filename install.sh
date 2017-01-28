#!/bin/sh
set -f

. install.inc

for file in $files; {
	test -z "$file" && continue
	source="${file%%,*}"
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
