#
# Copyright (c) 2016
# Dominic Fandrey <kamikaze@bsdforen.de>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# Include once.
test -n "$_bsda_opts_" && return 0
readonly _bsda_opts_=1

. ${bsda_dir:-.}/bsda_obj.sh

bsda:obj:createClass bsda:opts:Options \
	r:private:result \
	r:private:short \
	r:private:long \
	r:private:desc \
	r:private:next \
	i:private:init \
	c:private:clean \
	x:public:getopt \
	x:public:usage

bsda:opts:Options.init() {
	setvar ${this}result "$1"
	setvar ${this}short "$2"
	setvar ${this}long "$3"
	setvar ${this}desc "$4"
	unset ${this}next

	shift 4
	# Recursively create the next option
	if [ $# -gt 0 ]; then
		bsda:opts:Options ${this}next "$@"
	fi
}

bsda:opts:Options.clean() {
	local next
	$this.getNext next
	if [ -n "$next" ]; then
		$next.delete
	fi
}

bsda:opts:Options.getopt() {
	local result sopt lopt next retvar
	retvar="$1"
	shift
	$this.getShort sopt
	$this.getLong lopt
	$this.getResult result
	# Check argument against short option
	if [ -n "$sopt" -a -z "${1##${sopt}}" ]; then
		$caller.setvar "$retvar" "$result"
		return 0
	fi
	# Check argument against long option
	if [ -n "$lopt" -a -z "${1##${lopt}}" ]; then
		$caller.setvar "$retvar" "$result"
		return 0
	fi
	# Check argument against next option
	$this.getNext next
	if [ -n "$next" ]; then
		$next.getopt result "$@"
		$caller.setvar "$retvar" "$result"
		return 0
	fi
	# No options left
	return 1
}

bsda:opts:Options.usage() {
	local result next sopt lopt desc
	result=
	$this.getNext next
	if [ -n "$next" ]; then
		$next.usage result "$2"
	fi
	$this.getDesc desc
	if [ -n "$desc" ]; then
		$this.getShort sopt
		$this.getLong lopt
		result="$(printf "$2" "$sopt" "$lopt" "$desc")
$result"
	fi
	$caller.setvar "$1" "$result"
}

