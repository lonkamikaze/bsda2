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
