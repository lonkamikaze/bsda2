# Forward interruptions to a calling shell script
.INTERRUPT:
	@kill -INT ${BSDA_PID}

# Proceed with the Makefile
.include "Makefile"
