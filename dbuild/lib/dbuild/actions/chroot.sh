#!/usr/bin/env bash

while (( "${#DBUILD_ARGS}" )); do
	case "${DBUILD_ARGS[0]}" in
		--preserve-files|-p)
			export DBUILD_PRESERVE_FILES=y
			DBUILD_ARGS=("${DBUILD_ARGS[@]:1}")
			;;
		--args|-a)
			DBUILD_ARGS=("${DBUILD_ARGS[@]:1}")
			break
			;;
		--help|-h)
			msg "Usage: <options...> [--args|-a] <arguments...>"
			msg "Options:"
			msg "  --preserve-files, -p   Keeps the files changed"
			msg "  --args, -a             Pass all arguments to run a command in the chroot"
			msg "  --help, -h             List options and usage of the chroot action"
			exit 0
			;;
	esac
done

if [[ ! -f "${DBUILD_ROOTFS_DIR}.tar.gz" ]]; then
	msg_error "$(basename ${DBUILD_ROOTFS_DIR}.tar.gz) does not exist, please generate one."
	exit 1
fi

exit_chroot() {
	msg "Cleaning up chroot"
	rootfs_cleanup
	if [[ -z "${DBUILD_PRESERVE_FILES}" ]]; then
		msg "Removing chroot"
	else
		msg "Preserving changes"
		tar -cp --posix --xattrs -C "${DBUILD_ROOTFS_DIR}" . | gzip -c -9 > "${DBUILD_ROOTFS_DIR}.tar.gz"
	fi
	rm -rf "${DBUILD_ROOTFS_DIR}"
}

msg "Extracting tarball"
rm -rf "${DBUILD_ROOTFS_DIR}"
mkdir -p "${DBUILD_ROOTFS_DIR}"
tar -xf "${DBUILD_ROOTFS_DIR}.tar.gz" -C "${DBUILD_ROOTFS_DIR}"
trap "exit_chroot" EXIT
if [[ -z "${DBUILD_ARGS}" ]]; then
	if [[ -x "${DBUILD_ROOTFS_DIR}/$SHELL" ]]; then
		rootfs_exec "$SHELL"
	else
		rootfs_exec /usr/bin/bash
	fi
else
	rootfs_exec ${DBUILD_ARGS[@]}
fi
