#!/bin/sh
bsda_dir="${0%${0##*/}}"
. ${bsda_dir:-.}/bsda_tty.sh
bsda:tty:Terminal term
$term.use 6
$term.line 0 "--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
index=0
set +f
width=$(($(tput co || echo 80) - 6))
for file in *; do
	$term.stdout "$file"
	status="$(printf "%03d: %${width}s" $index "$file")"
	$term.line $((index % 5  + 1)) "$status"
	index=$((index + 1))
done
sleep 1
$term.stdout "$(ls -f)"
sleep 1
# Sleep to see whether status lines were preserved.
$term.delete
