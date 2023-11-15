#!/bin/sh

. install.inc

dirs=
for file in $files; {
	test -z "$file" && continue
	source="${file%%,*}"
	file="${file##*,}"
	target="${destdir}${file#${destdir:+/}}"
	if [ -n "${source}" -o -f "${target}" ]; then
		echo "deleting: $target"
		rm "$target"
		dirs="${dirs}${target%/*}"$'\n'
	fi
}
dirs="$(echo "${dirs}" | sort -ur)"
for dir in $dirs; do
	echo "remove: $dir"
	rmdir "${dir}"
done
