xbps() {
	local action="$1"
	shift 1
	XBPS_TARGET_ARCH="${TARGET_MACHINE}" XBPS_ARCH="${TARGET_MACHINE}" eval "xbps-$action" -r "${DBUILD_ROOTFS_DIR}" --cachedir "${XBPS_CACHE_DIR}" --config "${XBPS_CONFIG_DIR}" $@
}

binfmt_register() {
	local magic
	local mask
	local bin

	if [[ "${TARGET_ARCH}" != "${HOST_ARCH}" ]]; then
		case "${TARGET_ARCH}" in
			armv)
				magic="\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00"
				mask="\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff"
				bin=qemu-arm-static
				;;
			aarch64)
				magic="\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7"
				mask="\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff"
				bin=qemu-aarch64-static
				;;
			ppc64le)
				magic="\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x15\x00"
				mask="\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\x00"
				bin=qemu-ppc64le-static
				;;
			ppc64)
				magic="\x7fELF\x02\x02\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x15"
				mask="\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff"
				bin=qemu-ppc64-static
				;;
			ppc*)
				magic="\x7fELF\x01\x02\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x14"
				mask="\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff"
				bin=qemu-ppc-static
				;;
			mipsel*)
				magic="\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x08\x00"
				mask="\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff"
				bin=qemu-mipsel-static
				;;
			x86_64)
				magic="\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00"
				mask="\xff\xff\xff\xff\xff\xfe\xfe\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff"
				bin=qemu-x86_64-static
				;;
			i686)
				magic="\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00"
				mask="\xff\xff\xff\xff\xff\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff"
				bin=qemu-i386-static
				;;
			*)
				msg_error "Failed to register the binfmt: unsupported architecture"
				exit 1
				;;
		esac

		if ! mountpoint -q /proc/sys/fs/binfmt_misc; then
			modprobe -q binfmt_misc
			mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null
		fi

		if [ ! -f "/proc/sys/fs/binfmt_misc/qemu-${TARGET_ARCH}" ] ; then
			echo ":qemu-${TARGET_ARCH}:M::$magic:$mask:/usr/bin/$bin:" > /proc/sys/fs/binfmt_misc/register 2>/dev/null
		fi

		if [ ! -x "$DBUILD_ROOTFS_DIR/usr/bin/$bin" ]; then
			install -m755 -D $(whereis "$bin" | cut -f2 -d ' ') "$DBUILD_ROOTFS_DIR/usr/bin/$bin" || (msg_error "Failed to install $bin to rootfs"; exit 1)
		fi

		msg_debug "Registered binfmt: ${TARGET_ARCH}"
	fi
}

rootfs_pseudo_mount() {
	for f in dev proc sys; do
		[ ! -d "$DBUILD_ROOTFS_DIR/$f" ] && mkdir -p "$DBUILD_ROOTFS_DIR/$f"

		if ! mountpoint -q "$DBUILD_ROOTFS_DIR/$f"; then
			msg_debug "Binding host's /$f to rootfs"
			mount -r --bind "/$f" "$DBUILD_ROOTFS_DIR/$f"
		fi
	done

	if ! mountpoint -q "$DBUILD_ROOTFS_DIR/tmp"; then
		mkdir -p "$DBUILD_ROOTFS_DIR/tmp"
		msg_debug "Mounting tmp for rootfs"
		mount -o mode=0755,nosuid,nodev -t tmpfs tmpfs "$DBUILD_ROOTFS_DIR/tmp"
	fi
}

rootfs_pseudo_umount() {
	if [ -d "$DBUILD_ROOTFS_DIR" ]; then
		for f in dev proc sys; do
			msg_debug "Unmounting $f in rootfs"
			umount -l "$DBUILD_ROOTFS_DIR/$f" >/dev/null 2>&1 || umount -f "$DBUILD_ROOTFS_DIR/$f" >/dev/null 2>&1 || msg_debug "Failed to unmount $f in rootfs, may cause issues"
		done
	fi
	msg_debug "Unmounting tmp in rootfs"
	umount -l "$DBUILD_ROOTFS_DIR/tmp" >/dev/null 2>&1 || umount -f "$DBUILD_ROOTFS_DIR/tmp" >/dev/null 2>&1 || msg_debug "Failed to unmount tmp in rootfs, may cause issues"
}

rootfs_exec() {
	binfmt_register
	rootfs_pseudo_mount
	msg_debug "Running \"$1\" in rootfs"
	chroot "$DBUILD_ROOTFS_DIR" sh -c "$1"
}

rootfs_cleanup() {
	local bin

	rootfs_pseudo_umount

	if [[ "${TARGET_ARCH}" != "${HOST_ARCH}" ]]; then
		case "${TARGET_ARCH}" in
			armv)
				bin=qemu-arm-static
				;;
			aarch64)
				bin=qemu-aarch64-static
				;;
			ppc64le)
				bin=qemu-ppc64le-static
				;;
			ppc64)
				bin=qemu-ppc64-static
				;;
			ppc*)
				bin=qemu-ppc-static
				;;
			mipsel*)
				bin=qemu-mipsel-static
				;;
			x86_64)
				bin=qemu-x86_64-static
				;;
			i686)
				bin=qemu-i386-static
				;;
			*)
				msg_error "Failed to clean up rootfs: unrecognized architecture"
				exit 1
				;;
		esac

		if [[ -x "${DBUILD_ROOTFS_DIR}/usr/bin/$bin" ]]; then
			rm -rf "${DBUILD_ROOTFS_DIR}/usr/bin/$bin"
		fi

		msg_debug "Unregistered binfmt: ${TARGET_ARCH}"
	fi
}

find_blkdev() {
	local path="$1"
	if [[ -e "${DBUILD_ROOTFS_DIR}/etc/fstab" ]]; then
		while read p; do
			if [[ ! "$p" == \#* ]]; then
				local mnt_dev=$(echo "$p" | cut -f1 -d ' ')
				local mnt_path=$(echo "$p" | cut -f2 -d ' ')
				if [[ "${mnt_path}" == "${path}" ]]; then
					echo "${mnt_dev}"
					break
				fi
			fi
		done <"${DBUILD_ROOTFS_DIR}/etc/fstab"
	fi
}

find_disk() {
	local path="$1"
	for i in "${!DISK_IMAGES[@]}"; do
		local values=("${DISK_IMAGES[$i]}")
		local mnt_path=$(echo "$values" | cut -f3 -d ' ')
		if [[ "${mnt_path}" == "${path}" ]]; then
			echo "${values}"
			break
		fi
	done
}

enable_service() {
	while (( "$#" )); do
		if [[ ! -e "${DBUILD_ROOTFS_DIR}/etc/runit/runsvdir/default/$1" ]]; then
			ln -sf "/etc/sv/$1" "${DBUILD_ROOTFS_DIR}/etc/runit/runsvdir/default/$1"
		fi
		shift 1
	done
}

disable_service() {
	while (( "$#" )); do
		rm -rf "${DBUILD_ROOTFS_DIR}/etc/runit/runsvdir/default/$1"
		shift 1
	done
}

msg() {
	printf "[${DBUILD_ACTION}]: \033[0;32m$@\033[0m\n"
}

msg_error() {
	>&2 msg "\033[0;31m$@\033[0m"
}

msg_warn() {
	>&2 msg "\033[0;33m$@\033[0m"
}

msg_debug() {
	if [[ ! -z "${DBUILD_DEBUG}" ]]; then
		>&1 msg "\033[0;34m$@\033[0m"
	fi
}
