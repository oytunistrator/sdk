xbps() {
	local action="$1"
	shift 1
	XBPS_TARGET_ARCH="${EXPIDUS_SDK_ARCH}" XBPS_ARCH="${EXPIDUS_SDK_MACHINE}" eval "xbps-$action" -r "${EXPIDUS_SDK_ROOTFS_DIR}" --cachedir "${EXPIDUS_SDK_CACHE_DIR}/xbps" --config "/opt/expidus-sdk/etc/xbps.d" $@
}

rootfs_exec() {
	if [[ "${EXPIDUS_SDK_ARCH}" != $(uname -m) ]]; then
		if [[ ! -e "${EXPIDUS_SDK_ROOTFS_DIR}/usr/bin/qemu-${EXPIDUS_SDK_MACHINE%-musl}-static" ]]; then
			install -m755 -D $(whereis "qemu-${EXPIDUS_SDK_MACHINE%-musl}-static") "${EXPIDUS_SDK_ROOTFS_DIR}/usr/bin/qemu-${EXPIDUS_SDK_MACHINE%-musl}-static"
		fi
	fi

	proot -R "${EXPIDUS_SDK_ROOTFS_DIR}" -b /opt/expidus-sdk:/opt/expidus-sdk -b /var/cache:"${EXPIDUS_SDK_CACHE_DIR}" sh -c "$1"
}

msg() {
	printf "\033[0;32m$@\033[0m\n"
}

msg_error() {
	>&2 msg "\033[0;31m$@\033[0m"
}

msg_warn() {
	>&2 msg "\033[0;33m$@\033[0m"
}

msg_debug() {
	if [[ ! -z "${EXPIDUS_SDK_DEBUG}" ]]; then
		>&1 msg "\033[0;34m$@\033[0m"
	fi
}
