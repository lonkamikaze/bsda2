#!/bin/sh

. install.inc

dirs=
for file in $files; {
	test -z "$file" && continue
	file="${file##*,}"
	target="${destdir}${file#${destdir:+/}}"
	echo "deleting: $target"
	rm "$target"
	dirs="${dirs}${target%/*}"$'\n'
}
dirs="$(echo "${dirs}" | sort -ur)"
for dir in $dirs; do
	echo "remove: $dir"
	rmdir "${dir}"
done
