#
# Creates a list of all options for the port in the current location.
#
# The BSDA_GROUPS format is as follows:
#	${group}|${options}
#
# The options are a comma seperated list.
#
# The BSDA_OPTIONS format is as follows:
#	${group}|${opt}|${${opt}_IMPLIES}|${${opt}_PREVENTS}
#
# ${opt}_IMPLIES and ${opt}_PREVENTS are comma seperated lists of options.
#

.include "Makefile"

.for _grp in OPTIONS_DEFINE \
             ${OPTIONS_SINGLE:S,^,OPTIONS_SINGLE_,} \
             ${OPTIONS_RADIO:S,^,OPTIONS_RADIO_,} \
             ${OPTIONS_MULTI:S,^,OPTIONS_MULTI_,} \
             ${OPTIONS_GROUP:S,^,OPTIONS_GROUP_,}
.if ! empty(${_grp})
BSDA_GROUPS+=	${_grp}|${${_grp}:ts,}
.endif
.for _opt in ${${_grp}}
BSDA_OPTIONS+=	${_grp}|${_opt}|${${_opt}_IMPLIES:ts,}|${${_opt}_PREVENTS:ts,}
.endfor
.endfor
