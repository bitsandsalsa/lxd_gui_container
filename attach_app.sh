#!/bin/bash
#
# Wrapper to attach to running GUI app. Run on host.

# directory on host where bind mounts are created
readonly CONTAINER_MOUNTS_DIR=${HOME}/container_mounts

# number of times to connect to xpra server
declare -ri NUM_ATTEMPTS=10

readonly JQ_CMD="jq -rM"

function usage() {
    echo "$(basename $0) container-name app-cmdline [xpra-options...]"
    echo
}

function print_status() {
  echo "[+] $*"
}

function print_err() {
  echo "[!] $*"
}

if [ $# -lt 2 ]; then
    usage
    exit
fi

readonly CONTAINER_NAME=$1
shift
readonly APP_CMDLINE=$1
shift

# Check for running container #

container_info="$(lxc query \
  --wait "/1.0/containers/${CONTAINER_NAME}/state" 2>/dev/null)"
if [[ -n "${container_info}" ]]; then
    if [[ $(echo "${container_info}" | ${JQ_CMD} .status) != "Running" ]]; then
        print_status "Container not in \"Running\" state. Starting it."
        lxc start "${CONTAINER_NAME}" || exit 1
        lxc exec "${CONTAINER_NAME}" -- cloud-init status --wait || exit 1
        container_info="$(lxc query \
            --wait "/1.0/containers/${CONTAINER_NAME}/state" 2>/dev/null)"
    fi
else
    print_err "Container \"${CONTAINER_NAME}\" does not exist."
    exit 1
fi

# Start an xpra server in container for target app #

readonly container_ip="$(echo "${container_info}" \
  | ${JQ_CMD} '.network.eth0.addresses[] | select(.family == "inet").address')"
if [[ -z "${container_ip}" ]]; then
    print_err "Failed to determine container IP address."
    exit 1
fi

declare -ri display_num=${RANDOM}
# note that we add group permissions so that ACL mask is set
xpra start ssh://ubuntu@"${container_ip}"/${display_num} \
  --socket-permissions=660 \
  --start-child="${APP_CMDLINE}" \
  --exit-with-children \
  --start-via-proxy=no \
  --attach=no || exit 1

readonly XPRA_SOCK="${CONTAINER_MOUNTS_DIR}/${CONTAINER_NAME}/xpra/${CONTAINER_NAME}-${display_num}"

# Try to connect to xpra server #

declare -i try_count=0
while [ $((try_count++)) -lt ${NUM_ATTEMPTS} ]; do
    print_status "Attempt ${try_count}/${NUM_ATTEMPTS}: Connecting to xpra server."
    sleep 1
    if xpra version socket:"${XPRA_SOCK}"; then
        break
    fi
done

if [[ ${try_count} -ge ${NUM_ATTEMPTS} ]]; then
    print_err "Failed to connect to xpra server."
    exit 1
fi

xpra attach socket:"${XPRA_SOCK}" "$@" || exit 1
