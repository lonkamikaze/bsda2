#!/bin/sh

. install.inc

for file in $files; {
	test -z "$file" && continue
	file="${file##*,}"
	target="${destdir}${file#${destdir:+/}}"
	echo "deleting: $target"
	rm "$target"
}
test -n "$datadir" && rmdir "$destdir${datadir#${destdir:+/}}"
test -n "$datadir" && rmdir "$destdir${docsdir#${destdir:+/}}"
