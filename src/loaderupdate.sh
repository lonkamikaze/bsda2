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
# | E_LOADERUPDATE_EFIFILE    | error    | Invalid EFI loader provided       |
# | E_LOADERUPDATE_BOOTFS     | warning  | File system type not supported    |
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
	E_LOADERUPDATE_EFIFILE \
	E_LOADERUPDATE_BOOTFS=E_WARN \

. ${bsda_dir:-.}/bsda_opts.sh
. ${bsda_dir:-.}/bsda_elf.sh
. ${bsda_dir:-.}/bsda_fmt.sh
. ${bsda_dir:-.}/bsda_util.sh
. ${bsda_dir:-.}/lst.sh

#
# MBR system header.
#
# This is required to determine the DOS partition offset, the data
# before that offset should contain the protective MBR.
#
readonly loaderupdate_mbrh="/usr/include/sys/disk/mbr.h"

#
# Item in a linked list of EFI boot menu choices.
#
bsda:obj:createClass loaderupdate:BootChoice \
	a:public:BootChoice=loaderupdate:BootChoice \
	r:public:var     "The EFI variable this menu choice is stored under" \
	r:public:label   "The choice label in the boot menu" \
	w:public:action  "The action to take for this choice (delete, install, skip, force)" \
	i:private:init   "Construct the complete EFI boot menu choice"

#
# Construct an EFI boot menu choice.
#
loaderupdate:BootChoice.init() {
	setvar ${this}var "${1}"
	setvar ${this}label "${2}"
	setvar ${this}action "${3}"
}

#
# Item in a linked list of EFI partitions.
#
# Every EFI partition has a partition index and can be assigned a
# set of EFI boot menu choices.
#
# The boot menu choices should be associated with the loader location
# the new loader is supposed to be installed in.
#
bsda:obj:createClass loaderupdate:EfiPart \
	a:public:EfiPart=loaderupdate:EfiPart \
	a:public:BootChoice=loaderupdate:BootChoice \
	r:public:index            "Partition index" \
	r:private:lastBootChoice  "The last boot choice in the list of boot choices" \
	w:public:action           "The action to take (install, update, skip, force)" \
	w:public:label            "The desired EFI boot menu choice label" \
	x:public:bootChoices      "Create a flat list [rec] of boot choices" \
	x:public:addBootChoice    "Add a new boot choices" \
	i:private:init            "Initialise with index"

#
# Construct an EFI partition node.
#
loaderupdate:EfiPart.init() {
	setvar ${this}index "${1}"
	setvar ${this}lastBootChoice "${this}"
}

#
# Produce a flat list of the boot menu choices assigned to the loader
# location for this EFI partition, separated by the RS character.
#
# @param &1
#	The variable to store the list in
#
loaderupdate:EfiPart.bootChoices() {
	local next choices
	rec choices=
	$this.BootChoice next
	while [ -n "${next}" ]; do
		rec choices.push_back "${next}"
		$next.BootChoice next
	done
	$caller.setvar "${1}" "${choices}"
}

#
# Assign an EFI boot menu choice to this partition.
#
# @param 1
#	The EFI boot variable
# @param 2
#	The EFI boot label
# @param 3
#	The action to perform for this boot choice
#
loaderupdate:EfiPart.addBootChoice() {
	local last
	$this.getLastBootChoice last
	if loaderupdate:BootChoice ${last}BootChoice "$@"; then
		$last.BootChoice ${this}lastBootChoice
	fi
}

#
# Item in a linked list of classic BIOS compatible boot partitions.
#
bsda:obj:createClass loaderupdate:BootPart \
	a:public:BootPart=loaderupdate:BootPart \
	r:public:index   "Partition index" \
	w:public:action  "The action to take (update/install, skip, force)" \
	i:private:init   "Initialise with index"

#
# Construct a boot partition item.
#
# @param 1
#	The partition index
#
loaderupdate:BootPart.init() {
	setvar ${this}index "${1}"
}

#
# Item in a linked list of bootable devices.
#
# Retains information about boot partitions on a bootable device.
#
bsda:obj:createClass loaderupdate:Device \
	a:public:Device=loaderupdate:Device \
	a:private:BootPart=loaderupdate:BootPart \
	a:private:EfiPart=loaderupdate:EfiPart \
	r:public:name       "The name of the device" \
	r:public:scheme     "The detected partitioning scheme" \
	w:public:pmbrAct    "The action to take for the protective MBR (update/install, skip, force)" \
	x:public:bootParts  "Create a flat list [rec] of boot partitions" \
	x:public:efiParts   "Create a flat list [rec] of EFI partitions" \
	i:private:init      "Determine device properties"

#
# Produce a flat, RS separated list of boot partitions.
#
# @param &1
#	The variable to store the list in
#
loaderupdate:Device.bootParts() {
	local next parts
	$this.BootPart next
	rec parts=
	while [ -n "${next}" ]; do
		rec parts.push_back "${next}"
		$next.BootPart next
	done
	$caller.setvar "${1}" "${parts}"
}

#
# Produce a flat, RS separated list of EFI boot partitions.
#
# @param &1
#	The variable to store the list in
#
loaderupdate:Device.efiParts() {
	local next parts
	$this.EfiPart next
	rec parts=
	while [ -n "${next}" ]; do
		rec parts.push_back "${next}"
		$next.EfiPart next
	done
	$caller.setvar "${1}" "${parts}"
}

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
	local gpart scheme index type start size label attr \
	      bootPart efiPart
	setvar ${this}name "${1}"
	if ! gpart="$(/sbin/gpart backup "${1}" 2>&-)"; then
		bsda:err:raise E_LOADERUPDATE_NODEVICE "${0##*/}: ERROR: Cannot access device: $1"
		return 1
	fi
	bootPart=${this}
	efiPart=${this}
	scheme=
	while IFS=' ' read -r index type start size label attr; do
		case "${index}" in
		GPT)
			scheme="${index}"
		;;
		[0-9]*)
			case "${type}" in
			freebsd-boot)
				loaderupdate:BootPart ${bootPart}BootPart "${index}"
				$bootPart.BootPart bootPart
				;;
			efi)
				loaderupdate:EfiPart ${efiPart}EfiPart "${index}"
				$efiPart.EfiPart efiPart
				;;
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

	if [ -z "${bootPart#${this}}${efiPart#${this}}" ]; then
		bsda:err:raise E_LOADERUPDATE_NOPARTS \
		               "${0##*/}: ERROR: No freebsd-boot or efi partitions on device: ${1}"
		return 1
	fi
}

#
# Collect and verify a given list of devices.
#
# The Devices collections a tree of device information:
#
# - Devices: bootable devices container
#   - Device: linked list of bootable devices
#    - BootPart: linked list of classic boot loader partitions
#    - EfiPart:  linked list of EFI partitions
#      - BootChoice: EFI boot menu choices associated with the loader
#        to be installed
#
# @see loaderupdate:Device
#	For device requirements and properties
#
bsda:obj:createClass loaderupdate:Devices \
	a:private:Device=loaderupdate:Device \
	r:private:lastDevice  "The last device in the list of devices" \
	r:private:devs        "[rec] A list of already added devices" \
	x:public:devices      "Produce a flat list [rec] of all device objects" \
	i:public:add          "Construct or add to a list of devices"

#
# Produce a flat list of all device objects separated by the RS character.
#
# @param &1
#	Destination variable for the list of devices
#
loaderupdate:Devices.devices() {
	local devices device
	rec devices=
	$this.Device device
	while [ -n "${device}" ]; do
		rec devices.push_back "${device}"
		$device.Device device
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
	local name last
	for name in "$@"; do
		rec ${this}devs.contains "${name}" && continue
		$this.getLastDevice last
		if loaderupdate:Device ${last:=${this}}Device "${name}"; then
			$last.Device ${this}lastDevice
			rec ${this}devs.push_back "${name}"
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
	mountpoint="${2}"
	shift 2

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
		               "${0##*/}: WARNING: Failed to unmount: ${mountpoint}"
		return 0
	fi
	if [ -n "${mountpoint}" ] && \
	   ! /bin/rmdir "${mountpoint}"; then
		bsda:err:raise E_LOADERUPDATE_UMOUNT \
		               "${0##*/}: WARNING: Failed to remove: ${mountpoint}"
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
	r:private:bootfs   "The filesystem of the boot environment" \
	r:private:pmbr     "The protective MBR image path" \
	r:private:bootload "The freebsd-boot loader path" \
	r:private:efiload  "The efi loader path" \
	r:private:efilabel "The efi boot manager entry label" \
	r:private:efifile  "The install target on the efi partition" \
	r:private:efiarch  "EFI default path compatible architecture label" \
	i:private:init     "Initialise and run session" \
	x:private:all      "Add all viable devices" \
	x:private:matchimg "Compare images / block devices" \
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
# Compare the the given images / block devices using sha256.
#
# @param 1
#	Matching type, one of pmbr, bootload, file
# @param 2
#	The image file to match
# @param @
#	The image / block devices to compare
# @retval 0
#	The PMBR section of the given images/devices match
# @retval 1
#	Not all compared sections of the given images/devices match
#
loaderupdate:Session.matchimg() {
	local destdir type refsum chksum path cnt
	$this.getDestdir destdir

	type="${1}"
	shift

	case "${type}" in
	pmbr)
		cnt="$(/usr/bin/sed -En 's/^[[:space:]]*#define[[:space:]]+DOSPARTOFF[[:space:]]+//p' \
			                "${destdir%/}${loaderupdate_mbrh}")"
		cnt="${cnt%%[^0-9]*}"
		;;
	bootload)
		cnt="$(/usr/bin/stat -f%z "$1")"
		;;
	file)
		:
		;;
	*)
		bsda:err:raise E_FAIL \
		               "${0##*/}: ERROR: Match test not implemented for: ${type}"
		;;
	esac

	refsum=
	for path in "$@"; do
		case "${type}" in
		pmbr | bootload)
			chksum="$(/usr/bin/head -c"${cnt}" "${path}" | /sbin/sha256 -q)"
			;;
		file)
			chksum="$(/sbin/sha256 -q "${path}")"
			;;
		esac
		if [ "${refsum:=${chksum}}" != "${chksum}" ]; then
			return 1
		fi
	done
	return 0
}

#
# Parse command line arguments.
#
# @param @
#	The command line arguments
#
loaderupdate:Session.params() {
	local flags options devices option destdir devs kernelpath kernel \
	      msg e ostype version machine pmbr bootload efiload efilabel \
	      efifile efiarch
	bsda:opts:Flags ${this}Flags
	$this.Flags flags

	bsda:opts:Options options \
	ALL      -a  --all        'Update loaders of all devices' \
	BOOTFS   -B* --bootfs     'Override the filesystem detection, either ufs or zfs' \
	BOOTLOAD -b* --bootloader 'The freebsd-boot loader to install, e.g. /boot/gptboot' \
	COMPAT   -c  --compat     'Equivalent to -o/EFI/BOOT/BOOT{efiarch}.EFI' \
	EFILOAD  -e* --efiloader  'The EFI loader to install, e.g. /boot/loader.efi' \
	PMBR     -p* --pmbr       'The protective MBR image, e.g. /boot/pmbr' \
	EFILABEL -L* --label      'The EFI Boot Manager entry label' \
	EFIFILE  -o* --efifile    'The EFI install target, e.g. /efi/{ostype}/boot{machine}.efi' \
	NOEFI    -n  --noefi      'Do not create EFI Boot Manager entries' \
	DRYRUN   -D  --dry-run    'Print the actions that would be performed' \
	DESTDIR  -d* --destdir    'The root containing /boot' \
	DUMP     -P  --dump       'Show the detected partitioning' \
	QUIET    -q  --quiet      'Do not produce any additional output' \
	HELP     -h  --help       'Display the list of command arguments' \
	FORCE    -f  --force      'Force update of already up to date loaders'
	$caller.delete $options

	loaderupdate:Devices ${this}Devices
	$this.Devices devices

	destdir="$(/usr/bin/printenv DESTDIR)"
	bootfs=
	bootload=
	efiload=
	pmbr=
	efilabel=
	efifile=

	while [ $# -gt 0 ]; do
		$options.getopt option "$1"
		$flags.add "${option}"
		case "$option" in
		ALL)
			$this.all
		;;
		DRYRUN | DUMP | NOEFI | QUIET | FORCE)
		;;
		DESTDIR)
			destdir="${1#-d}"
			destdir="${destdir#--destdir}"
			if [ -z "${destdir}" ]; then
				destdir="${2}"
				shift
			fi
		;;
		BOOTFS)
			bootfs="${1#-B}"
			bootfs="${bootfs#--bootfs}"
			if [ -z "${bootfs}" ]; then
				bootfs="${2}"
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
		EFIFILE)
			efifile="${1#-o}"
			efifile="${efifile#--efifile}"
			if [ -z "${efifile}" ]; then
				efifile="${2}"
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
		COMPAT)
			efifile='/EFI/BOOT/BOOT{efiarch}.EFI'
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

	# only --dump may be performed without a device, unless it is combined
	# with --dry-run, which makes a device mandatory
	$devices.devices devs
	if ($flags.check DUMP -eq 0 || $flags.check DRYRUN) && [ -z "${devs}" ]; then
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

	# according to the table in uefi(8)
	case "${machine}" in
	amd64) efiarch=X64;;
	arm)   efiarch=ARM;;
	arm64) efiarch=AA64;;
	i386)  efiarch=IA32;;
	riscv) efiarch=RISCV64;;
	*)     efiarch="${machine}";;
	esac
	setvar ${this}efiarch "${efiarch}"

	if $flags.check BOOTFS; then
		case "${bootfs}" in
		ufs | zfs) ;;
		*)
			bsda:err:raise E_LOADERUPDATE_PARAM \
			               "${0##*/}: ERROR: Option -B unsupported file system type: ${bootfs}"
		;;
		esac
	else
		bootfs="$(/sbin/mount -p | /usr/bin/awk -vDESTDIR="${destdir:-/}" '
			$2 == DESTDIR && $0 = $3
		')"
		bootfs="${bootfs##*$'\n'}"
	fi
	setvar ${this}bootfs "${bootfs}"

	case "${bootfs}" in
	ufs) bootload="${bootload:-/boot/gptboot}";;
	zfs) bootload="${bootload:-/boot/gptzfsboot}";;
	'')  bsda:err:raise E_LOADERUPDATE_BOOTFS \
	                    "${0##*/}: WARNING: Failed to detect boot filesystem type";;
	*)   bsda:err:raise E_LOADERUPDATE_BOOTFS \
	                    "${0##*/}: WARNING: Unsupported boot filesystem type: ${bootfs}";;
	esac
	setvar ${this}bootload "${bootload}"

	efiload="${efiload:-/boot/loader.efi}"
	setvar ${this}efiload "${efiload}"

	pmbr="${pmbr:-/boot/pmbr}"
	setvar ${this}pmbr "${pmbr}"

	efilabel="${efilabel:-"{version} {arch} [{pdev}]"}"
	bsda:err:collect
	bsda:fmt:printf "${efilabel}" > /dev/null \
	                dev= pdev= index=0 version= arch= efiarch= ostype=
	while bsda:err:get e msg; do
		bsda:err:forward E_LOADERUPDATE_EFILABEL \
		                 "${msg}" \
		                 '       Note, EFI label may use:' \
		                 '           {dev}, {pdev}, {index}, {version}, {arch}, {efiarch}, {ostype}'
		return 1
	done
	setvar ${this}efilabel "${efilabel}"

	if $flags.check EFIFILE && $flags.check COMPAT; then
		bsda:err:raise E_LOADERUPDATE_EFIFILE \
		               "${0##*/}: ERROR: The -o and -c options are mutually exclusive"
		return 1
	fi

	if [ "${machine}" = "${efiarch}" ] && $flags.check COMPAT -eq 1; then
		bsda:err:raise E_LOADERUPDATE_EFIFILE \
		               "${0##*/}: ERROR: The -c option is not supported for the architecture: ${machine}" \
		               '       Ignore this error by supplying -c twice: -cc'
		return 1
	fi

	efifile="${efifile:-"/efi/{ostype}/boot{arch}.efi"}"
	bsda:err:collect
	bsda:fmt efifile "${efifile}" \
	         arch="${machine}" ostype="${ostype}" efiarch="${efiarch}"
	while bsda:err:get e msg; do
		bsda:err:forward E_LOADERUPDATE_EFIFILE \
		                 "${msg}" \
		                 '       Note, EFI file may use:' \
		                 '           {arch}, {ostype}, {efiarch}'
		return 1
	done

	if [ -n "${efifile##/*}" ]; then
		bsda:err:raise E_LOADERUPDATE_EFIFILE \
		               "${0##*/}: ERROR: The EFI file location must begin with a '/': ${efifile}"
		return 1
	fi
	setvar ${this}efifile "${efifile}"
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
#	An action classification for the command. If set to skip,
#	the printout of the command is preceded by the `#` character.
#	Other values are ignored.
# @param 2
#	The command to print
# @param @
#	The command arguments
#
loaderupdate:Session.printcmd() {
	local IFS flags cmd arg
	tail=
	IFS=' '
	cmd="${2##*/}"
	test "${1}" = "skip" && cmd="#[skip] ${cmd}"
	shift 2
	$this.Flags flags
	if $flags.check QUIET -eq 0; then
		if $flags.check DRYRUN; then
			echo -n "${cmd}"
		elif [ -t 1 ]; then
			printf "\033[38;5;112m%s\033[m> %s" "${0##*/}" "${cmd}"
		else
			echo -n "${0##*/}> ${cmd}"
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
# @param 1
#	An action classification for the command. If set to skip,
#	the command is not executed. Other values are ignored.
# @param @
#	The command to execute
# @return
#	The exit code of the given command
# @throws E_LOADERUPDATE_CMD
#	In case the command fails
#
loaderupdate:Session.runcmd() {
	local IFS flags e action
	IFS=' '
	action="$1"
	shift
	$this.Flags flags
	if [ "${action}" != "skip" ] && $flags.check DRYRUN -eq 0; then
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
# @param 1
#	An action classification for the command. If set to skip,
#	the command is not executed and the printout of the command
#	is preceded by the `#` character. Other values are ignored.
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
	      pmbr bootload efiload efilabel efifile devname bootparts efiparts \
	      part i efivars ecompat label efiarch action dev mount mountpoint \
	      var varfile varlabel etc partdev skipaction efi boot choice choices \

	$this.Devices devs
	$devs.devices devs
	rec devs.set_ifs

	$this.getDestdir  destdir
	$this.getOstype   ostype
	$this.getVersion  version
	$this.getMachine  machine
	$this.getBootfs   bootfs
	$this.getPmbr     pmbr
	$this.getBootload bootload
	$this.getEfiload  efiload
	$this.getEfilabel efilabel
	$this.getEfifile  efifile
	$this.getEfiarch  efiarch
	pmbr="${pmbr:+${destdir}/${pmbr#/}}"
	bootload="${bootload:+${destdir}/${bootload#/}}"
	efiload="${efiload:+${destdir}/${efiload#/}}"

	$this.Flags flags

	efivars=
	ecompat=
	if $flags.check NOEFI -eq 0; then
		efivars="$(/usr/sbin/efibootmgr -v 2>&1)"
		# FreeBSD 13 broke the -a, -A and -B parameters by
		# requiring an additional parameter
		case "$(/usr/sbin/efibootmgr -h 2>&1)" in
		*'-b bootnum'*) ecompat=b;;
		esac
	fi
	skipaction=skip
	$flags.check FORCE && skipaction=force

	# walk the partitions and determine the actions to be taken
	for dev in ${devs}; do
		$dev.bootParts bootparts
		$dev.efiParts  efiparts
		$dev.getName   devname
		# check whether all required loaders are readable
		if rec efiparts.is_not_empty; then
			if [ -z "${efivars}" ] && $flags.check NOEFI -eq 0; then
				bsda:err:raise E_LOADERUPDATE_EFIBOOTMGR \
				               "${0##*/}: ERROR: Failed to query efibootmgr, are you a super user?"
				return 1
			fi
			if ! [ -f "${efiload}" -a -r "${efiload}" ]; then
				bsda:err:raise E_LOADERUPDATE_LOADER \
				               "${0##*/}: ERROR: Cannot read EFI loader: ${efiload}"
				return 1
			fi
		fi
		if rec bootparts.is_not_empty; then
			if ! [ -f "${pmbr}" -a -r "${pmbr}" ]; then
				bsda:err:raise E_LOADERUPDATE_LOADER \
				               "${0##*/}: ERROR: Cannot read protective MBR: ${pmbr}"
				return 1
			fi
			if $this.matchimg pmbr "${pmbr}" "/dev/${devname}"; then
				setvar ${dev}pmbrAct ${skipaction}
			else
				setvar ${dev}pmbrAct update/install
			fi
			if [ -z "${bootload}" ]; then
				bsda:err:raise E_LOADERUPDATE_LOADER \
				               "${0##*/}: ERROR: No freebsd-boot loader selected, select via -B or -b"
				return 1
			fi
			if ! [ -f "${bootload}" -a -r "${bootload}" ]; then
				bsda:err:raise E_LOADERUPDATE_LOADER \
				               "${0##*/}: ERROR: Cannot read freebsd-boot loader: ${bootload}"
				return 1
			fi
		fi
		# for each efi partition check whether it should
		# install, skip or update
		for efi in ${efiparts}; do
			$efi.getIndex part
			partdev="${devname}p${part}"
			mountpoint="/tmp/${0##*/}.$$/${partdev}"
			# create a read only mount
			loaderupdate:Mount mount \
					   "/dev/${partdev}" \
					   "${mountpoint}" \
					   -tmsdosfs -oro \
			|| return $?
			# check whether loader is installed
			# and verify sha256 checksum
			if ! [ -r "${mountpoint}${efifile}" ]; then
				setvar ${efi}action install
			elif $this.matchimg file "${efiload}" "${mountpoint}${efifile}"; then
				setvar ${efi}action ${skipaction}
			else
				setvar ${efi}action update
			fi
			$mount.delete
			# set a label for the EFI partition
			$flags.check NOEFI && continue
			bsda:fmt label \
				 "${efilabel}" \
				 dev="${devname}" \
				 pdev="${devname}p${part}" \
				 index="${part}" \
				 version="${version}" \
				 arch="${machine}" \
				 efiarch="${efiarch}" \
				 ostype="${ostype}" || return $?
			setvar ${efi}label "${label}"

			#
			# determine efi variables set for the loader location
			# in this partition
			#
			# - to begin with mark all of them for `delete`
			# - afterwards go through the list to find one
			#   that is up to date and set it to `skip` or
			#   `force` (if --force is set)
			# - if no entries are up to date select the first
			#   one and mark it for `update`
			# - if there are no entries create one for install
			#
			while IFS=' ' read -r var varlabel; do
				case "${var}" in
				*Boot[0-9]*)
					IFS=' ' read -r varfile etc
					test "${varfile}" = "${partdev}:${efifile}" || continue
					var="${var#*Boot}"
					var="${var%\*}"
					$efi.addBootChoice "${var}" "${varlabel% HD(*)/File(*)}" delete
				;;
				esac
			done <<- EFIVARS
			${efivars}
			EFIVARS

			$efi.bootChoices choices
			$efi.getLabel label
			action=
			# find skip label
			for choice in ${choices}; do
				$choice.getLabel varlabel
				if [ "${varlabel}" = "${label}" ]; then
					action="${skipaction}"
					$choice.setAction "${action}"
					break
				fi
			done
			# find update label
			if [ -z "${action}" ] && rec choices[1] choice; then
				action="update"
				$choice.setAction "${action}"
			fi
			# no EFI boot menu entries associated with the loader,
			# install one
			if [ -z "${action}" ]; then
				$efi.addBootChoice "" "${label}" install
			fi
		done
		for boot in ${bootparts}; do
			$boot.getIndex part
			if $this.matchimg bootload "${bootload}" "/dev/${devname}p${part}"; then
				setvar ${boot}action ${skipaction}
			else
				setvar ${boot}action update/install
			fi
		done
	done

	if $flags.check DUMP; then
		echo   "Boot Environment"
		echo   "----------------"
		printf "%-22s  %s\n" \
		       "destdir:"             "${destdir:-/}" \
		       "ostype:"              "${ostype}" \
		       "kernel version:"      "${version}" \
		       "kernel arch:"         "${machine}" \
		       "filesystem:"          "${bootfs}" \
		       "protective MBR:"      "${pmbr}" \
		       "freebsd-boot loader:" "${bootload}" \
		       "EFI loader:"          "${efiload}"
		echo
		for dev in ${devs}; do
			$dev.getName devname
			$dev.bootParts bootparts
			$dev.efiParts efiparts
			printf "Device %s\n-------%.${#devname}s\n" "${devname}" "----------------"
			if rec bootparts.is_not_empty; then
				$dev.getPmbrAct action
				printf "    %-18s  %s\n" "${action}:" "${pmbr} > ${devname}"
			fi
			for boot in ${bootparts}; do
				$boot.getIndex part
				$boot.getAction action
				printf "    %-18s  %s\n" "${action}:" "${bootload} > ${devname}p${part}"
			done
			for efi in ${efiparts}; do
				$efi.getIndex part
				$efi.getAction action
				printf "    %-18s  %s\n" "${action}:" "${efiload} > ${devname}p${part}:${efifile}"
				$flags.check NOEFI && continue
				# list boot menu choices
				$efi.bootChoices choices
				for choice in ${choices}; do
					$choice.getVar var
					$choice.getLabel label
					$choice.getAction action
					printf "    %-18s  %s%s\n" "${action} EFI label:" "${label}" "${var:+" (Boot${var})"}"
					if [ "${action}" = "update" ]; then
						$efi.getLabel label
						printf "    %-18s  %s\n" "" "${label}"
					fi
				done
			done
			echo
		done
		# --dump implies nothing is modified,
		# so bail if this is not a --dry-run
		$flags.check DRYRUN || return 0
	fi

	# all pre-checks passed, commit/demo changes
	for dev in ${devs}; do
		$dev.getName devname
		$this.printcmd print "# Device ${devname}"

		$dev.bootParts bootparts
		$dev.efiParts efiparts

		# install freebsd-boot loader
		if rec bootparts.is_not_empty; then
			$dev.getPmbrAct action
			$this.cmd "${action}" /sbin/gpart bootcode -b"${pmbr}" "${devname}" \
			|| return 1
		fi
		for boot in ${bootparts}; do
			$boot.getIndex part
			$boot.getAction action
			$this.cmd "${action}" /sbin/gpart bootcode -p"${bootload}" \
			                                  -i"${part}" "${devname}" \
			|| return 1
		done

		# install EFI loader
		for efi in ${efiparts}; do
			$efi.getIndex part
			$efi.getAction action
			partdev="${devname}p${part}"
			mountpoint="/tmp/${0##*/}.$$/${partdev}"
			$this.printcmd "${action}" mkdir -p "${partdev}"
			$this.printcmd "${action}" mount -tmsdosfs -osync \
			                                 "/dev/${partdev}" "${partdev}"
			if [ "${action}" != "skip" ] && $flags.check DRYRUN -eq 0; then
				loaderupdate:Mount mount \
				                   "/dev/${partdev}" \
				                   "${mountpoint}" \
				                   -tmsdosfs -osync \
				|| return $?
				$caller.delete ${mount}
			fi
			$this.printcmd "${action}" mkdir -p "${partdev}${efifile%/*}"
			$this.runcmd "${action}" /bin/mkdir -p "${mountpoint}${efifile%/*}" \
			|| return $?
			$this.printcmd "${action}" cp "${efiload}" "${partdev}${efifile}"
			$this.runcmd "${action}" /bin/cp "${efiload}" "${mountpoint}${efifile}" \
			|| return $?

			$flags.check NOEFI && continue

			# update EFI boot menu choices
			$efi.getLabel label
			$efi.bootChoices choices
			for choice in ${choices}; do
				$choice.getVar var
				$choice.getAction action
				case "${action}" in delete | update | skip | force)
					$this.cmd "${action}" /usr/sbin/efibootmgr -B${ecompat} "${var}" || return $?
					;;
				esac
				case "${action}" in install | update | skip | force)
					$this.cmd "${action}" /usr/sbin/efibootmgr -ac${var:+b} ${var} -l "${partdev}:${efifile}" -L "${label}" || return $?
					;;
				esac
			done
		done
	done
}

#
# Print usage message.
#
loaderupdate:Session.help() {
	local usage
	$1.usage usage "\t%2.2s, %-12s  %s\n"
	echo "usage: loaderupdate [[-d destdir] [-L efilabel] [-B {ufs, zfs}] [-b bootloader]
	            [-e efiloader] [-o efifile] [-p pmbr] [-cDfnq] device ...
       loaderupdate [-d destdir] [-L efilabel] [-B {ufs, zfs}] [-b bootloader]
                    [-e efiloader] [-o efifile] [-p pmbr] [-cDfnq] -a
       loaderupdate [-d destdir] [-L efilabel] [-B {ufs, zfs}] [-b bootloader]
                    [-e efiloader] [-o efifile] [-p pmbr] [-cDfnq] -P [-a | device ...]
       loaderupdate -h
$(echo -n "$usage" | /usr/bin/sort -f)"
}
