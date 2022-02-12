test -n "$_loaderupdate_" && return 0
readonly _loaderupdate_=1

. ${bsda_dir:-.}/bsda_err.sh

#
# Error/exit codes for error reporting.
#
# | Code                      | Severity | Meaning                           |
# |---------------------------|----------|-----------------------------------|
# | E_LOADERUPDATE_PARAM      | error    | Invalid or conflicting arguments  |
# | E_LOADERUPDATE_NODEVICE   | error    | Cannot access device              |
# | E_LOADERUPDATE_DESTDIR    | error    | DESTDIR is not a directory        |
# | E_LOADERUPDATE_NOKERNEL   | error    | Cannot access kernel              |
# | E_LOADERUPDATE_EFILABEL   | error    | Invalid EFI label                 |
# | E_LOADERUPDATE_SCHEME     | error    | Unsupported partitioning scheme   |
# | E_LOADERUPDATE_NOPARTS    | error    | No freebsd-boot or efi partitions |
# | E_LOADERUPDATE_EFIBOOTMGR | error    | Failed to run efibootmgr          |
# | E_LOADERUPDATE_LOADER     | error    | Cannot access loader image        |
# | E_LOADERUPDATE_MOUNT      | error    | Failed to mount efi partition     |
# | E_LOADERUPDATE_UMOUNT     | warning  | Failed to unmount efi partition   |
# | E_LOADERUPDATE_CMD        | error    | Failed to execute command         |
#
bsda:err:createECs \
	E_LOADERUPDATE_PARAM \
	E_LOADERUPDATE_NODEVICE \
	E_LOADERUPDATE_DESTDIR \
	E_LOADERUPDATE_NOKERNEL \
	E_LOADERUPDATE_EFILABEL \
	E_LOADERUPDATE_SCHEME \
	E_LOADERUPDATE_NOPARTS \
	E_LOADERUPDATE_EFIBOOTMGR \
	E_LOADERUPDATE_LOADER \
	E_LOADERUPDATE_MOUNT \
	E_LOADERUPDATE_UMOUNT=E_WARN \
	E_LOADERUPDATE_CMD \

. ${bsda_dir:-.}/bsda_opts.sh
. ${bsda_dir:-.}/bsda_elf.sh
. ${bsda_dir:-.}/bsda_fmt.sh
. ${bsda_dir:-.}/bsda_util.sh

#
# Retains information about boot partitions on a bootable device.
#
bsda:obj:createClass loaderupdate:Device \
	a:private:Next=loaderupdate:Device \
	r:public:dev       "The name of the device" \
	r:public:scheme    "The detected partitioning scheme" \
	r:public:bootparts "List of freebsd-boot partition indices" \
	r:public:efiparts  "List of efi partition indices" \
	i:private:init     "Determine device properties"

#
# Collect information about and verify the given device.
#
# In order for initialisation to complete the following conditions
# must be met:
#
# @param 1
#	The name of the device
# @retval 0
#	The instance was initialised successfully
# @retval 1
#	The device does not meet requirements
# @throws E_LOADERUPDATE_NODEVICE
#	gpart(1) was not able to access the device
# @throws E_LOADERUPDATE_SCHEME
#	The device is not formatted using the GUID Partition Table scheme
# @throws E_LOADERUPDATE_NOPARTS
#	Neither efi nor freebsd-boot partitions are present
#
loaderupdate:Device.init() {
	local gpart scheme bootparts efiparts index type start size label attr
	setvar ${this}dev "${1}"
	if ! gpart="$(/sbin/gpart backup "${1}" 2>&-)"; then
		bsda:err:raise E_LOADERUPDATE_NODEVICE "${0##*/}: ERROR: Cannot access device: $1"
		return 1
	fi
	scheme=
	bootparts=
	efiparts=
	while IFS=' ' read -r index type start size label attr; do
		case "${index}" in
		GPT)
			scheme="${index}"
		;;
		[0-9]*)
			case "${type}" in
			freebsd-boot) bootparts="${bootparts}${index}"$'\n';;
			efi)          efiparts="${efiparts}${index}"$'\n';;
			esac
		;;
		esac
	done <<- GPART
	${gpart}
	GPART

	if [ -z "${scheme}" ]; then
		bsda:err:raise E_LOADERUPDATE_SCHEME \
		               "${0##*/}: ERROR: Unsupported partitioning scheme on device: ${1}"
		return 1
	fi
	setvar ${this}scheme "${scheme}"

	if [ -z "${bootparts}${efiparts}" ]; then
		bsda:err:raise E_LOADERUPDATE_NOPARTS \
		               "${0##*/}: ERROR: No freebsd-boot or efi partitions on device: ${1}"
		return 1
	fi
	setvar ${this}bootparts "${bootparts}"
	setvar ${this}efiparts "${efiparts}"
}

#
# Collect and verify a given list of devices.
#
# @see loaderupdate:Device
#	For device requirements and properties
#
bsda:obj:createClass loaderupdate:Devices \
	a:private:First=loaderupdate:Device \
	r:private:devs     "A list of already added devices" \
	x:public:devices   "Produce a flat list of all device objects" \
	i:public:add       "Construct/add to a list of devices"

#
# Produce a flat list of all device objects.
#
# @param &1
#	Destination variable for the list of devices
#
loaderupdate:Devices.devices() {
	local devices device
	devices=
	$this.First device
	while [ -n "${device}" ]; do
		devices="${devices}${device}"$'\n'
		getvar device ${device}Next
	done
	$caller.setvar "${1}" "${devices}"
}

#
# Build/append to the device list of verified devices.
#
# @param @
#	A list of device names
# @see loaderupdate:Device.init()
#
loaderupdate:Devices.add() {
	local name device dst devs
	dst=${this}First
	$this.getDevs devs
	$this.First device
	while [ -n "${device}" ]; do
		dst=${device}Next
		getvar device ${device}Next
	done
	for name in "$@"; do
		bsda:util:in "${name}" ${devs} && continue
		if loaderupdate:Device device "${name}"; then
			setvar ${dst} ${device}
			dst=${device}Next
			devs="${devs}${name}"$'\n'
			setvar ${this}devs "${devs}"
			setvar ${this}last "${device}"
		fi
	done
}

#
# Mount lifetime class.
#
# Performs a mount on initialisation and unmount on finalisation.
#
bsda:obj:createClass loaderupdate:Mount \
	r:private:device     "The device path to mount" \
	r:private:mountpoint "The mountpoint to mount to" \
	i:private:init       "Perform mount(8)" \
	c:private:clean      "Perform umount(8)"

#
# Create the given mountpoint and mount the given device.
#
# @param 1
#	The device to mount
# @param 2
#	The mountpoint
# @param @
#	Additional arguments to the mount command
# @retval 0
#	The mount succeeded
# @retval 1
#	The mount failed
# @throws E_LOADERUPDATE_MOUNT
#	Failed to create mountpoint or failed to mount
#
loaderupdate:Mount.init() {
	local device mountpoint nullfs
	device="${1}"
	shift
	mountpoint="${1}"
	shift

	if ! /bin/mkdir -p "${mountpoint}"; then
		bsda:err:raise E_LOADERUPDATE_MOUNT \
		               "${0##*/}: ERROR: Failed to create mountpoint: ${mountpoint}"
		return 1
	fi
	setvar ${this}mountpoint "${mountpoint}"
	nullfs="$(/sbin/mount -p | /usr/bin/awk -vDEV="${device}" '$1 == DEV && $0=$2')"
	if [ -n "${nullfs}" ]; then
		# fall back to a nullfs mount if the device is already mounted
		device="${nullfs%%$'\n'*}"
		set -- -t nullfs
	fi
	if ! /sbin/mount "$@" "${device}" "${mountpoint}"; then
		bsda:err:raise E_LOADERUPDATE_MOUNT \
		               "${0##*/}: ERROR: Failed to mount device: ${device}"
		return 1
	fi
	setvar ${this}device "${device}"
}

#
# Unmount and remove the mountpoint.
#
# @throws E_LOADERUPDATE_UMOUNT
#	Warn if umount or mountpoint removal fails
#
loaderupdate:Mount.clean() {
	local device mountpoint
	$this.getDevice device
	$this.getMountpoint mountpoint
	if [ -n "${device}" ] && \
	   ! /sbin/umount "${mountpoint}" 2>&- && \
	   ! /sbin/umount -f "${mountpoint}"; then
		bsda:err:raise E_LOADERUPDATE_UMOUNT \
		               "WARNING: Failed to unmount: ${mountpoint}"
		return 0
	fi
	if [ -n "${mountpoint}" ] && \
	   ! /bin/rmdir "${mountpoint}"; then
		bsda:err:raise E_LOADERUPDATE_UMOUNT \
		               "WARNING: Failed to remove: ${mountpoint}"
		return 0
	fi
	# gracefully delete empty parent folders
	/bin/rmdir -p "${mountpoint%/*}" 2>&-
	return 0
}

#
# The session class for loaderupdate.
#
bsda:obj:createClass loaderupdate:Session \
	a:private:Flags=bsda:opts:Flags \
	a:private:Devices=loaderupdate:Devices \
	r:private:destdir  "The boot environment mountpoint" \
	r:private:ostype   "The kernel ostype" \
	r:private:version  "The kernel version" \
	r:private:machine  "The kernel machine architecture" \
	r:private:bootfs   "The file system of the boot environment" \
	r:private:pmbr     "The protective MBR image path" \
	r:private:bootload "The freebsd-boot loader path" \
	r:private:efiload  "The efi loader path" \
	r:private:efilabel "The efi boot manager entry label" \
	i:private:init     "Initialise and run session" \
	x:private:all      "Add all viable devices" \
	x:private:params   "Parse command line arguments" \
	x:private:printcmd "Print the given command" \
	x:private:runcmd   "Run the given command" \
	x:private:cmd      "Print and run the given command" \
	x:private:run      "Perform the boot loader update" \
	x:private:help     "Print a usage message"

#
# Initialise and run the session.
#
# @param @
#	The command line arguments
#
loaderupdate:Session.init() {
	$this.params "$@" || return $?
	$this.run || return $?
}

#
# Add all physical providers listed by `gpart show`.
#
# Convert errors to notes.
#
loaderupdate:Session.all() {
	local devices devs e msg
	$this.Devices devices
	bsda:err:collect
	# take all devices gpart suggests and intersect them with the
	# list of physical providers
	devs="$(/sbin/gpart show 2>&- | /usr/bin/awk '/^=>/ && $0=$4')"
	devs="$(/usr/sbin/gstat -pbI0 2>&- \
	        | /usr/bin/awk 'NR>2 && $0=$10' \
	        | /usr/bin/grep -Fx "${devs}")"
	$devices.add ${devs}
	while bsda:err:get e msg; do
		bsda:err:forward E_WARN "${0##*/}: WARNING: ${msg#*ERROR: }"
	done
}

#
# Parse command line arguments.
#
# @param @
#	The command line arguments
#
loaderupdate:Session.params() {
	local flags options devices option destdir devs kernelpath kernel \
	      msg e ostype version machine pmbr bootload efiload efilabel
	bsda:opts:Flags ${this}Flags
	$this.Flags flags

	bsda:opts:Options options \
	ALL      -a  --all        'Update loaders of all devices' \
	BOOTLOAD -b* --bootloader 'The freebsd-boot loader to install, e.g. /boot/gptboot' \
	EFILOAD  -e* --efiloader  'The EFI loader to install, e.g. /boot/loader.efi' \
	PMBR     -p* --pmbr       'The protective MBR image, e.g. /boot/pmbr' \
	EFILABEL -L* --label      'The EFI Boot Manager entry label' \
	NOEFI    -n  --noefi      'Do not create EFI Boot Manager entries' \
	DRYRUN   -D  --dry-run    'Print the actions that would be performed' \
	DESTDIR  -d* --destdir    'The root containing /boot' \
	DUMP     -P  --dump       'Show the detected partitioning' \
	QUIET    -q  --quiet      'Do not produce any additional output' \
	HELP     -h  --help       'Display the list of command arguments'
	$caller.delete $options

	loaderupdate:Devices ${this}Devices
	$this.Devices devices

	destdir="$(/usr/bin/printenv DESTDIR)"
	bootload=
	efiload=
	pmbr=
	efilabel=

	while [ $# -gt 0 ]; do
		$options.getopt option "$1"
		case "$option" in
		ALL)
			$this.all
			$flags.add "${option}"
		;;
		DRYRUN | DUMP | NOEFI | QUIET)
			$flags.add "${option}"
		;;
		DESTDIR)
			destdir="${1#-d}"
			destdir="${destdir#--destdir}"
			if [ -z "${destdir}" ]; then
				destdir="${2}"
				shift
			fi
		;;
		BOOTLOAD)
			bootload="${1#-b}"
			bootload="${bootload#--bootload}"
			if [ -z "${bootload}" ]; then
				bootload="${2}"
				shift
			fi
		;;
		EFILOAD)
			efiload="${1#-e}"
			efiload="${efiload#--efiload}"
			if [ -z "${efiload}" ]; then
				efiload="${2}"
				shift
			fi
		;;
		PMBR)
			pmbr="${1#-p}"
			pmbr="${pmbr#--pmbr}"
			if [ -z "${pmbr}" ]; then
				pmbr="${2}"
				shift
			fi
		;;
		EFILABEL)
			efilabel="${1#-L}"
			efilabel="${efilabel#--label}"
			if [ -z "${efilabel}" ]; then
				efilabel="${2}"
				shift
			fi
		;;
		HELP)
			$this.help "$options"
			exit 0
		;;
		OPT_UNKNOWN)
			bsda:err:raise E_LOADERUPDATE_PARAM "${0##*/}: ERROR: Unknown parameter: \"${1}\""
			return 1
		;;
		OPT_SPLIT)
			eval "$bsda_opts_split"
			continue
		;;
		OPT_NOOPT)
			$devices.add "${1}"
		;;
		esac
		shift
	done

	if $flags.check DRYRUN -ne 0 && $flags.check DUMP -ne 0; then
		bsda:err:raise E_LOADERUPDATE_PARAM "${0##*/}: ERROR: The -D and -P flags are mutually exclusive"
		return 1
	fi

	$devices.devices devs
	if $flags.check DUMP -eq 0 && [ -z "${devs}" ]; then
		$this.help "$options"
		bsda:err:raise E_LOADERUPDATE_NODEVICE "${0##*/}: ERROR: No device selected"
		return 1
	fi

	destdir="${destdir%/}"
	if [ -n "${destdir}" ] && ! [ -d "${destdir}" ]; then
		bsda:err:raise E_LOADERUPDATE_DESTDIR "${0##*/}: ERROR: DESTDIR is not a directory: ${destdir}"
		return 1
	fi
	setvar ${this}destdir "${destdir}"

	kernelpath="${destdir}/boot/kernel/kernel"
	if ! [ -r "${kernelpath}" ]; then
		bsda:err:raise E_LOADERUPDATE_NOKERNEL "${0##*/}: ERROR: Cannot access kernel: ${kernelpath}"
		return 1
	fi
	bsda:err:collect
	bsda:elf:File kernel "${kernelpath}"
	$caller.delete $kernel
	while bsda:err:get e msg; do
		case "${e}" in
		E_BSDA_ELF_NOENT)
			bsda:err:forward E_LOADERUPDATE_NOKERNEL \
			                 "${0##*/}: ERROR: Failed to load kernel: ${kernelpath}";;
		*)
			bsda:err:forward "${e}" "${msg}";;
		esac
		return 1
	done
	$kernel.fetch version version
	if [ -z "${version}" ]; then
		bsda:err:raise E_LOADERUPDATE_NOKERNEL \
		               "${0##*/}: ERROR: Failed to read kernel version: ${kernelpath}"
		return 1
	fi
	$kernel.fetch machine machine
	if [ -z "${machine}" ]; then
		bsda:err:raise E_LOADERUPDATE_NOKERNEL \
		               "${0##*/}: ERROR: Failed to read kernel machine architecture: ${kernelpath}"
		return 1
	fi
	$kernel.fetch ostype ostype
	if [ -z "${ostype}" ]; then
		bsda:err:raise E_LOADERUPDATE_NOKERNEL \
		               "${0##*/}: ERROR: Failed to read kernel ostype: ${kernelpath}"
		return 1
	fi
	if [ -n "${version##${ostype}*}" ]; then
		# the version must start with the ostype
		version="${ostype} ${version}"
	fi
	setvar ${this}version "${version%%$'\n'*}"
	setvar ${this}machine "${machine}"
	setvar ${this}ostype "${ostype}"

	bootfs="$(/sbin/mount -p | /usr/bin/awk -vDESTDIR="${destdir:-/}" '
		$2 == DESTDIR && $0 = $3
	')"
	bootfs="${bootfs##*$'\n'}"
	setvar ${this}bootfs "${bootfs}"

	case "${bootfs}" in
	ufs) bootload="${bootload:-/boot/gptboot}";;
	zfs) bootload="${bootload:-/boot/gptzfsboot}";;
	esac
	setvar ${this}bootload "${bootload}"

	efiload="${efiload:-/boot/loader.efi}"
	setvar ${this}efiload "${efiload}"

	pmbr="${pmbr:-/boot/pmbr}"
	setvar ${this}pmbr "${pmbr}"

	efilabel="${efilabel:-"{version} {arch} [{pdev}]"}"
	bsda:err:collect
	bsda:fmt:printf "${efilabel}" > /dev/null \
	                dev= pdev= index=0 version= arch=
	while bsda:err:get e msg; do
		bsda:err:forward E_LOADERUPDATE_EFILABEL \
		                 "${msg}" \
		                 '       Note, EFI label may use:' \
		                 '           {dev}, {pdev}, {index}, {version}, {arch}'
		return 1
	done
	setvar ${this}efilabel "${efilabel}"
}

#
# Print the given command.
#
# The command is stripped of a leading path and and prefixed with
# `loaderupdate> `.
#
# The following flags affect the execution:
#
# | Flag   | Effect                                     |
# |--------|--------------------------------------------|
# | QUIET  | Suppress output                            |
# | DRYRUN | Do not prefix output with `loaderupdate> ` |
#
# @param 1
#	The command to print
# @param @
#	The command arguments
#
loaderupdate:Session.printcmd() {
	local IFS flags cmd arg
	IFS=' '
	cmd="${1}"
	shift
	$this.Flags flags
	if $flags.check QUIET -eq 0; then
		if $flags.check DRYRUN -ne 0; then
			echo -n "${cmd##*/}"
		elif [ -t 1 ]; then
			printf "\033[38;5;112m%s\033[m> %s" "${0##*/}" "${cmd##*/}"
		else
			echo -n "${0##*/}> ${cmd##*/}"
		fi
		for arg in "$@"; do
			case "${arg}" in
			--*)    echo -n " ${arg}";;
			-?*\ *) echo -n " ${arg%${arg#-?}}'${arg#-?}'";;
			*\ *)   echo -n " '${arg}'";;
			*)      echo -n " ${arg}";;
			esac
		done
		echo
	fi
}

#
# Execute the given command.
#
# The DRYRUN flag deactivates command execution.
#
# @param @
#	The command to execute
# @return
#	The exit code of the given command
# @throws E_LOADERUPDATE_CMD
#	In case the command fails
#
loaderupdate:Session.runcmd() {
	local IFS flags e
	IFS=' '
	$this.Flags flags
	if $flags.check DRYRUN -eq 0; then
		"$@"
		e=$?
		if [ ${e} -ne 0 ]; then
			bsda:err:raise E_LOADERUPDATE_CMD \
			               "${0##*/}: ERROR: Command failed with error ${e}: ${*}"
		fi
		return ${e}
	fi
}

#
# Print and execute the given command.
#
# @param @
#	The command to execute
# @return
#	The exit code of the given command
# @throws E_LOADERUPDATE_CMD
#	In case the command fails
# @see loaderupdate.Session.printcmd()
# @see loaderupdate.Session.runcmd()
#
loaderupdate:Session.cmd() {
	$this.printcmd "$@"
	$this.runcmd "$@"
}

#
# Perform the actions requested by the user.
#
# @throws E_LOADERUPDATE_NODEVICE
#	gpart(1) was not able to access a device
# @throws E_LOADERUPDATE_SCHEME
#	A device is not formatted using the GUID Partition Table scheme
# @throws E_LOADERUPDATE_NOPARTS
#	Neither efi nor freebsd-boot partitions are present on a device
# @throws E_LOADERUPDATE_MOUNT
#	Failed to create a mountpoint or failed to mount
# @throws E_LOADERUPDATE_CMD
#	In case a command fails
#
loaderupdate:Session.run() {
	local IFS flags devs destdir ostype version machine bootfs \
	      pmbr bootload efiload efilabel efifile dev bootparts efiparts \
	      part i efivars ecompat demo quiet label
	IFS=$'\n'

	$this.Devices devs
	$devs.devices devs

	$this.getDestdir  destdir
	$this.getOstype   ostype
	$this.getVersion  version
	$this.getMachine  machine
	$this.getBootfs   bootfs
	$this.getPmbr     pmbr
	$this.getBootload bootload
	$this.getEfiload  efiload
	$this.getEfilabel efilabel
	pmbr="${destdir}/${pmbr#/}"
	bootload="${destdir}/${bootload#/}"
	efiload="${destdir}/${efiload#/}"
	efifile="/efi/${ostype}/boot${machine}.efi"

	$this.Flags flags
	if $flags.check DUMP -ne 0; then
		echo   "Boot Environment"
		echo   "----------------"
		printf "%-22s  %s\n" \
		       "destdir:"             "${destdir:-/}" \
		       "ostype:"              "${ostype}" \
		       "kernel version:"      "${version}" \
		       "kernel arch:"         "${machine}" \
		       "file system:"         "${bootfs}" \
		       "protective MBR:"      "${pmbr}" \
		       "freebsd-boot loader:" "${bootload}" \
		       "EFI loader:"          "${efiload}"
		for dev in ${devs}; do
			$dev.getBootparts bootparts
			$dev.getEfiparts  efiparts
			$dev.getDev       dev
			printf "\nDevice %s\n-------%.${#dev}s\n" "${dev}" "----------------"
			if [ -n "${bootparts}" ]; then
				printf "    %-18s  %s\n" "install:" "${pmbr} > ${dev}"
			fi
			for part in ${bootparts}; do
				printf "    %-18s  %s\n" "install:" "${bootload} > ${dev}p${part}"
			done
			for part in ${efiparts}; do
				printf "    %-18s  %s\n" "install:" "${efiload} > ${dev}p${part}:${efifile}"
			done
			$flags.check NOEFI -ne 0 && efiparts=
			for part in ${efiparts}; do
				bsda:fmt label "${efilabel}" \
				         dev="${dev}" \
				         pdev="${dev}p${part}" \
				         index="${part}" \
				         version="${version}" \
				         arch="${machine}" || return $?
				printf "    %-18s  %s\n" \
				       "EFI boot entry:" "${label}"
			done
		done
		return 0
	fi

	efivars=
	ecompat=
	if $flags.check NOEFI -eq 0; then
		efivars="$(/usr/sbin/efibootmgr -v 2>&1)"
		# FreeBSD 13 broke the -a, -A and -B parameters by
		# requiring an additional parameteter
		case "$(/usr/sbin/efibootmgr -h 2>&1)" in
		*'-b bootnum'*) ecompat=b;;
		esac
	fi

	# check whether all required loaders are readable
	for dev in ${devs}; do
		$dev.getBootparts bootparts
		$dev.getEfiparts  efiparts
		$dev.getDev       dev
		if [ -n "${efiparts}" ]; then
			if [ -z "${efivars}" ] && $flags.check NOEFI -eq 0; then
				bsda:err:raise E_LOADERUPDATE_EFIBOOTMGR \
				               "${0##*/}: ERROR: Failed to query efibootmgr, are you a super user?"
				return 1
			fi
			if ! [ -r "${efiload}" ]; then
				bsda:err:raise E_LOADERUPDATE_LOADER \
				               "${0##*/}: ERROR: Cannot read EFI loader: ${efiload}"
				return 1
			fi
		fi
		if [ -n "${bootparts}" ]; then
			if ! [ -r "${pmbr}" ]; then
				bsda:err:raise E_LOADERUPDATE_LOADER \
				               "${0##*/}: ERROR: Cannot read protective MBR: ${pmbr}"
				return 1
			fi
			if ! [ -r "${bootload}" ]; then
				bsda:err:raise E_LOADERUPDATE_LOADER \
				               "${0##*/}: ERROR: Cannot read freebsd-boot loader: ${bootload}"
				return 1
			fi
		fi
	done

	# all pre-checks passed, commit/demo changes
	local mount mountpoint var varfile etc partdev
	for dev in ${devs}; do
		$dev.getBootparts bootparts
		$dev.getEfiparts  efiparts
		$dev.getDev       dev

		# install freebsd-boot loader
		if [ -n "${bootparts}" ]; then
			$this.cmd /sbin/gpart bootcode -b"${pmbr}" "${dev}" \
			|| return 1
		fi
		for part in ${bootparts}; do
			$this.cmd /sbin/gpart bootcode -p"${bootload}" \
			                      -i"${part}" "${dev}" \
			|| return 1
		done

		# install EFI loader
		for part in ${efiparts}; do
			partdev="${dev}p${part}"
			mountpoint="/tmp/${0##*/}.$$/${partdev}"
			$this.printcmd mkdir -p "${partdev}"
			$this.printcmd mount -tmsdosfs -osync \
			               "/dev/${partdev}" "${partdev}"
			if $flags.check DRYRUN -eq 0; then
				loaderupdate:Mount mount \
				                   "/dev/${partdev}" \
				                   "${mountpoint}" \
				                   -tmsdosfs -osync \
				|| return $?
				$caller.delete ${mount}
			fi
			$this.printcmd mkdir -p "${partdev}${efifile%/*}"
			$this.runcmd /bin/mkdir -p "${mountpoint}${efifile%/*}" \
			|| return $?
			$this.printcmd cp "${efiload}" "${partdev}${efifile}"
			$this.runcmd /bin/cp "${efiload}" "${mountpoint}${efifile}" \
			|| return $?
		done

		# clear old EFI boot manager entries
		while IFS=' ' read -r var etc; do
			case "${var}" in
			*Boot[0-9]*)
				IFS=' ' read -r varfile etc
				test "${varfile}" = "${partdev}:${efifile}" || continue
				var="${var#*Boot}"
				var="${var%\*}"
				$this.cmd /usr/sbin/efibootmgr -B${ecompat} "${var}" \
				|| return $?
			;;
			esac
		done <<- EFIVARS
		${efivars}
		EFIVARS

		# make EFI boot manager entry
		$flags.check NOEFI -ne 0 && efiparts=
		for part in ${efiparts}; do
			partdev="${dev}p${part}"
			mountpoint="/tmp/${0##*/}.$$/${partdev}"
			bsda:fmt label "${efilabel}" \
			         dev="${dev}" \
			         pdev="${partdev}" \
			         index="${part}" \
			         version="${version}" \
			         arch="${machine}" || return $?
			$this.cmd /usr/sbin/efibootmgr \
			          -cl "${partdev}:${efifile}" -L "${label}" \
			|| return $?
			while IFS=' ' read -r var etc; do
				case "${var}" in
				*Boot[0-9]*)
					IFS=' ' read -r varfile etc
					test "${varfile}" = "${partdev}:${efifile}" || continue
					var="${var#*Boot}"
					var="${var%\*}"
					$this.cmd /usr/sbin/efibootmgr -a${ecompat} "${var}" \
					|| return $?
				;;
				esac
			done <<- EFIVARS
			$(/usr/sbin/efibootmgr -v 2>&1)
			EFIVARS
		done
	done
}

#
# Print usage message.
#
loaderupdate:Session.help() {
	local usage
	$1.usage usage "\t%2.2s, %-12s  %s\n"
	echo "usage: loaderupdate [-d destdir] [-L efilabel] [-b bootloader] [-e efiloader]
                    [-p pmbr] [-Dn] device ...
       loaderupdate [-d destdir] [-L efilabel] [-b bootloader] [-e efiloader]
                    [-p pmbr] [-Dn] -a
       loaderupdate [-d destdir] [-L efilabel] [-b bootloader] [-e efiloader]
                    [-p pmbr] [-n] -P [-a | device ...]
       loaderupdate -h
$(echo -n "$usage" | /usr/bin/sort -f)"
}
