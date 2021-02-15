#!/usr/bin/env bash

while (( "${#DBUILD_ARGS}" )); do
	case "${DBUILD_ARGS[0]}" in
		--help|-h)
			msg "Usage: \033[1mnone\033[00m"
			exit 0
			;;
	esac
done

if [[ -f  "${DBUILD_ROOTFS_DIR}.tar.gz" ]]; then
	msg_warn "$(basename ${DBUILD_ROOTFS_DIR}.tar.gz) already exists, will be overwritten"
fi

mkdir -p "${DBUILD_ROOTFS_DIR}"
mkdir -p "${DBUILD_ROOTFS_DIR}/var/db/xbps/keys"
cp "${DBUILD_LIB_DIR}/repo-keys"/*.plist "${DBUILD_ROOTFS_DIR}/var/db/xbps/keys/"

msg "Syncing repositories"
xbps install -R "${XBPS_REPO}" -S >/dev/null

msg "Installing packages"
xbps install -R "${XBPS_REPO}" -yu "${PACKAGES[@]}" >/dev/null

KERNEL_SERIES=$(xbps query -S linux | grep pkgver | cut -f2 -d '-' | cut -f1 -d '_')
KERNEL_VERSION=$(xbps query -S "linux${KERNEL_SERIES}" | grep pkgver | cut -f2 -d '-')

msg "Configuring system"
sed -i -e "s|HOSTNAME=.*|HOSTNAME=\"${HOSTNAME}\"|g" -e 's|#HOSTNAME|HOSTNAME|g' "${DBUILD_ROOTFS_DIR}/etc/rc.conf"
msg_debug "Hostname set to ${HOSTNAME}"

sed -i -e "s|TIMEZONE=.*|TIMEZONE=\"${TIMEZONE}\"|g" -e 's|#TIMEZONE|TIMEZONE|g' "${DBUILD_ROOTFS_DIR}/etc/rc.conf"
echo "${HOSTNAME}" >"${DBUILD_ROOTFS_DIR}/etc/hostname"
ln -sf /usr/share/zoneinfo/"${TIMEZONE}" "${DBUILD_ROOTFS_DIR}/etc/localtime"
msg_debug "Timezone set to ${TIMEZONE}"

msg "Reconfiguring packages"
rootfs_exec "xbps-reconfigure --all --force" >/dev/null

if [[ -z "${SKIP_SERVICES}" ]]; then
	msg "Configuring system services"
	enable_service agetty-serial polkitd uuidd "${ENABLED_SERVICES[@]}"
	msg_debug "Enabled services: agetty-serial polkitd uuidd ${ENABLED_SERVICES[@]}"
	if [[ ! -z "${DISABLED_SERVICES}" ]]; then
		disable_service "${DISABLED_SERVICES[@]}"
		msg_debug "Disabled services: ${DISABLED_SERVICES[@]}"
	fi
fi

rootfs_cleanup
msg "Compressing rootfs and cleaning up"
tar -cp --posix --xattrs -C "${DBUILD_ROOTFS_DIR}" . | gzip -c -9 > "${DBUILD_ROOTFS_DIR}.tar.gz"
rm -rf "${DBUILD_ROOTFS_DIR}"
