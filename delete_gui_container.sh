#!/bin/bash
#
# Delete a container and associated resources that were created by the "create"
# tool.

# directory on host where bind mounts are created
readonly CONTAINER_MOUNTS_DIR=${HOME}/container_mounts

function usage() {
  echo "$(basename $0) container-name"
  echo
}

function print_status() {
  echo "[+] $*"
}

function print_err() {
  echo "[!] $*"
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

readonly CONTAINER_NAME=$1
shift

# name of profile to use
readonly PROFILE_NAME="${CONTAINER_NAME}"

lxc stop "${CONTAINER_NAME}" 2>/dev/null

print_status "Deleting container \"${CONTAINER_NAME}\"."
lxc delete "${CONTAINER_NAME}"

# delete profile AFTER associated containers are deleted
print_status "Deleting profile \"${PROFILE_NAME}\"."
lxc profile delete "${PROFILE_NAME}"

readonly mount_dir="${CONTAINER_MOUNTS_DIR}/${CONTAINER_NAME}"
readonly share_dir="${mount_dir}/share"
# fail if the file sharing bind mount is not empty
rmdir "${share_dir}" || exit 1
print_status "Deleting container mount directory \"${mount_dir}\"."
rm -r "${mount_dir}"
