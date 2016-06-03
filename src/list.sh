#!/bin/sh
set -fCe

. install.inc

for file in $files; {
	test -z "$file" && continue
	file="${file##*,}"
	target="${destdir}${file#${destdir:+/}}"
	echo "$target"
}

