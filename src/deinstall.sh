#!/bin/sh -f

. install.inc

for file in $files; {
	test -z "$file" && continue
	target="${file##*,}"
	echo "deleting: $target"
	rm "$target"
}

