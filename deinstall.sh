#!/bin/sh -f

. install.inc

for file in $files; {
	test -z "$file" && continue
	target="${destdir}${file##*,}"
	echo "deleting: $target"
	rm "$target"
}
test -n "$datadir" && rmdir "$destdir$datadir"
test -n "$datadir" && rmdir "$destdir$docsdir"
