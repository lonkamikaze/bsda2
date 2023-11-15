#!/bin/sh
set -fCe

. install.inc

for file in $files; {
	source="${file%%,*}"
	test -z "${source}" && continue
	file="${file##*,}"
	target="${destdir}${file#${destdir:+/}}"
	echo "$target"
}

