#
# Copyright (c) 2006-2009, 2016
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

# Default locations
BUILDFLAGS_PARSER?=    %%DATADIR%%/buildflags.awk
BUILDFLAGS_CONF?=      %%PREFIX%%/etc/buildflags.conf
BUILDFLAGS_USER?=      ${HOME}/.buildflags.conf
BUILDFLAGS_TMP?=       %%TMP%%/buildflags.tmp.mk.${USER}

BUILDFLAGS_DISTCC?=    %%PREFIX%%/bin/distcc
BUILDFLAGS_CCACHE?=    %%PREFIX%%/bin/ccache

# Parse configurations
.if exists(${BUILDFLAGS_CONF}) && exists(${BUILDFLAGS_USER)
BUILDFLAGS!=           test    "${BUILDFLAGS_TMP}" -nt "${BUILDFLAGS_CONF}" \
                            -a "${BUILDFLAGS_TMP}" -nt "${BUILDFLAGS_USER}" \
                       || "${BUILDFLAGS_PARSER}" "${BUILDFLAGS_USER}" \
                                                 "${BUILDFLAGS_CONF}" \
                          > "${BUILDFLAGS_TMP}"; echo
.elif exists(${BUILDFLAGS_CONF})
BUILDFLAGS!=           test    "${BUILDFLAGS_TMP}" -nt "${BUILDFLAGS_CONF}" \
                       || "${BUILDFLAGS_PARSER}" "${BUILDFLAGS_CONF}" \
                          > "${BUILDFLAGS_TMP}"; echo
.elif exists(${BUILDFLAGS_USER})
BUILDFLAGS!=           test    "${BUILDFLAGS_TMP}" -nt "${BUILDFLAGS_USER}" \
                       || "${BUILDFLAGS_PARSER}" "${BUILDFLAGS_USER}" \
                          > "${BUILDFLAGS_TMP}"; echo
.endif

# Include generated make file
.sinclude "${BUILDFLAGS_TMP}"

# Use ccache and distcc.
.if defined(USE_CCACHE) && !${CC:M*ccache*} && exists(${BUILDFLAGS_CCACHE}) && defined(USE_DISTCC) && !${CC:M*distcc*} && exists(${BUILDFLAGS_DISTCC})
CC:=			env CCACHE_PREFIX=${BUILDFLAGS_DISTCC} ${BUILDFLAGS_CCACHE} ${CC}
CPP:=			env CCACHE_PREFIX=${BUILDFLAGS_DISTCC} ${BUILDFLAGS_CCACHE} ${CPP}
CXX:=			env CCACHE_PREFIX=${BUILDFLAGS_DISTCC} ${BUILDFLAGS_CCACHE} ${CXX}
# Use distcc.
.elif defined(USE_DISTCC) && !${CC:M*distcc*} && exists(${BUILDFLAGS_DISTCC}) && !${CC:M*ccache*}
CC:=			${BUILDFLAGS_DISTCC} ${CC}
CPP:=			${BUILDFLAGS_DISTCC} ${CPP}
CXX:=			${BUILDFLAGS_DISTCC} ${CXX}
# Use ccache.
.elif defined(USE_CCACHE) && !${CC:M*ccache*} && exists(${BUILDFLAGS_CCACHE}) && !${CC:M*distcc*}
CC:=			${BUILDFLAGS_CCACHE} ${CC}
CPP:=			${BUILDFLAGS_CCACHE} ${CPP}
CXX:=			${BUILDFLAGS_CCACHE} ${CXX}
.endif

# Activate normal parallel builds.
.if defined(THREADS)
.MAKEFLAGS:		-j${THREADS}
.endif
