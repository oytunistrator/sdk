#!/usr/bin/env bash

ROOT_PASSWORD="expidus"

while (( "${#DBUILD_ARGS}" )); do
	case "${DBUILD_ARGS[0]}" in
		--help|-h)
			msg "Usage: <options...>"
			msg "Options:"
			msg "  --package, -p          Adds another package to install, can be used multiple times"
			msg "  --enable-service, -e   Enables a service, can be used multiple times"
			msg "  --disable-service, -d  Disables a service, can be used multiple times"
			msg "  --root-password, -r    Sets the root password, will be encrypted"
			msg "  --add-user, -a         Adds another user, can be used multiple times"
			msg "  --hostname, -h         Sets the hostname"
			msg "  --timezone, -t         Sets the timezone"
			exit 0
			;;
		--package|-p)	
			PACKAGES+=("${DBUILD_ARGS[1]}")
			DBUILD_ARGS=("${DBUILD_ARGS[@]:2}")
			;;
		--enable-service|-e)
			ENABLED_SERVICES+=("${DBUILD_ARGS[1]}")
			DBUILD_ARGS=("${DBUILD_ARGS[@]:2}")
			;;
		--disable-service|-d)
			DISABLED_SERVICES+=("${DBUILD_ARGS[1]}")
			DBUILD_ARGS=("${DBUILD_ARGS[@]:2}")
			;;
		--root-password|-r)
			ROOT_PASSWORD="$2"
			DBUILD_ARGS=("${DBUILD_ARGS[@]:2}")
			;;
		--add-user|-a)
			ADDITIONAL_USERS+=("${DBUILD_ARGS[1]}")
			DBUILD_ARGS=("${DBUILD_ARGS[@]:2}")
			;;
		--hostname|-h)
			HOSTNAME="${DBUILD_ARGS[1]}"
			DBUILD_ARGS=("${DBUILD_ARGS[@]:2}")
			;;
		--timezone|-t)
			TIMEZONE="${DBUILD_ARGS[1]}"
			DBUILD_ARGS=("${DBUILD_ARGS[@]:2}")
			;;
		*)
			msg_error "Invalid argument ${DBUILD_ARGS[0]}"
			exit 1
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

msg "Configuring system"
sed -i -e "s|HOSTNAME=.*|HOSTNAME=\"${HOSTNAME}\"|g" -e 's|#HOSTNAME|HOSTNAME|g' "${DBUILD_ROOTFS_DIR}/etc/rc.conf"
msg_debug "Hostname set to ${HOSTNAME}"

sed -i -e "s|TIMEZONE=.*|TIMEZONE=\"${TIMEZONE}\"|g" -e 's|#TIMEZONE|TIMEZONE|g' "${DBUILD_ROOTFS_DIR}/etc/rc.conf"
echo "${HOSTNAME}" >"${DBUILD_ROOTFS_DIR}/etc/hostname"
ln -sf /usr/share/zoneinfo/"${TIMEZONE}" "${DBUILD_ROOTFS_DIR}/etc/localtime"
msg_debug "Timezone set to ${TIMEZONE}"

sed -i -e "s|LANG=.*|LANG=\"${LANG}\"|g" "${DBUILD_ROOTFS_DIR}/etc/locale.conf"
sed -i -e "s|#${LANG}|${LANG}|g" "${DBUILD_ROOTFS_DIR}/etc/default/libc-locales"
msg_debug "Language set to ${LANG}"

msg "Reconfiguring packages"
rootfs_exec "xbps-reconfigure --all --force >/dev/null 2>&1"

rootfs_adduser() {
	local p="$1"
	user_name=$(echo "$p" | cut -f1 -d ' ')
	user_pword=$(echo "$p" | cut -f2 -d ' ')
	adduser_opts="${p/${user_name} ${user_pword} /}"
	if [[ ! -z "${NOT_LIVE}" ]] && [[ "${user_name}" == "expidus" ]]; then
		msg_warn "Skipping live user"
	else
		msg "Adding user ${user_name}"
		eval useradd "${user_name}" ${adduser_opts} -R "${DBUILD_ROOTFS_DIR}"
		if [[ "$user_pword" == "-" ]]; then
			passwd -R "${DBUILD_ROOTFS_DIR}" -d "${user_name}"
		else
			echo "${user_name}:${user_pword}" | chpasswd -R "${DBUILD_ROOTFS_DIR}" -c SHA512
		fi
	fi
}

if [[ -z "${SKIP_USERS}" ]]; then
	msg "Configuring users"
	while read p; do
		rootfs_adduser "$p"
	done < "${DBUILD_LIB_DIR}/users"

	if [[ -f "${HOME}/.config/expidus-sdk/dbuild/users" ]]; then
		while read p; do
			rootfs_adduser "$p"
		done < "${HOME}/.config/expidus-sdk/dbuild/users"
	fi

	if [[ ! -z "${ADDITIONAL_USERS}" ]]; then
		for p in ${ADDITIONAL_USERS[@]}; do
			rootfs_adduser "$p"
		done
	fi

	msg "Setting root user password"
	echo "root:${ROOT_PASSWORD}" | chpasswd -R "${DBUILD_ROOTFS_DIR}" -c SHA512

	if [[ -z "${NOT_LIVE}" ]]; then
		msg "Configuring live system"
		sed -i -e 's|autologin-user=.*|autologin-user=expidus|g' -e 's|autologin-session=.*|autologin-session=expidus|g' \
			-e 's|#autologin-user=|autologin-user=|g' -e 's|#autologin-session=|autologin-session=|g' "${DBUILD_ROOTFS_DIR}/etc/lightdm/lightdm.conf"

		ENABLED_SERVICES+=(lightdm)
		DISABLED_SERVICES+=(agetty-tty1)
	fi
fi

if [[ -z "${SKIP_SERVICES}" ]]; then
	msg "Configuring system services"
	enable_service agetty-serial polkitd uuidd "${ENABLED_SERVICES[@]}"
	msg_debug "Enabled services: agetty-serial polkitd uuidd ${ENABLED_SERVICES[@]}"
	if [[ ! -z "${DISABLED_SERVICES}" ]]; then
		disable_service "${DISABLED_SERVICES[@]}"
		msg_debug "Disabled services: ${DISABLED_SERVICES[@]}"
	fi
fi

if type get_kernel_version >/dev/null 2>&1; then
	KERNEL_VERSION=$(get_kernel_version)
else
	KERNEL_SERIES=$(xbps query -S linux | grep pkgver | cut -f2 -d '-' | cut -f1 -d '_')
	KERNEL_VERSION=$(xbps query -S "linux${KERNEL_SERIES}" | grep pkgver | cut -f2 -d '-')
fi

if type post_build_rootfs >/dev/null 2>&1; then
	msg "Running post hook"
	post_build_rootfs
fi

rootfs_cleanup
msg "Compressing rootfs and cleaning up"
tar -cp --posix --xattrs -C "${DBUILD_ROOTFS_DIR}" . | gzip -c -9 > "${DBUILD_ROOTFS_DIR}.tar.gz"
rm -rf "${DBUILD_ROOTFS_DIR}"
