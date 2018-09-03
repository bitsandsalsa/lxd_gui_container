#!/bin/bash
#
# Bind mount file(s) into a GUI container.

# TODO: newlines in filenames will cause problems

readonly CONTAINER_MOUNTS_DIR=${HOME}/container_mounts
readonly WINDOW_TITLE='File Mapper'

function list_containers() {
    find "${CONTAINER_MOUNTS_DIR}" -mindepth 1 -maxdepth 1 -type d -printf "%f\0"
}

function select_container() {
    zenity \
      --title="${WINDOW_TITLE}" \
      --window-icon=question \
      --list \
      --text='Step 1 of 2: Select container' \
      --hide-header \
      --column='container name'
}

function cleanup() {
    for file_id in "${!mapped_files[@]}"; do
        lxc config device remove "${container}" "${mapped_devices[${file_id}]}"
        lxc exec "${container}" -- rm "${mapped_container_paths[${file_id}]}"
        echo "${mapped_acls[${file_id}]}" | setfacl --set-file=- "${mapped_files[${file_id}]}"
    done
}

function wait() {
    zenity \
      --title="${WINDOW_TITLE}" \
      --window-icon=info \
      --list \
      --text="Files to unmap in container \"${container}\" (selections are ignored)" \
      --column='host path' \
      "${mapped_files[@]}"
}

function list_xpra_sessions() {
    zenity \
      --title="${WINDOW_TITLE}" \
      --progress \
      --text='Waiting for lxc command to complete...' \
      --pulsate \
      --no-cancel \
      --auto-close \
      </dev/zero \
      &

    lxc exec "${container}" -- sudo -u ubuntu -i xpra list \
      | grep 'LIVE session at'

    kill %
}

# Obtain list of containers #
readonly container=$(list_containers | select_container)

[ -z "${container}" ] && exit

declare -A mapped_files mapped_devices mapped_container_paths mapped_acls
declare -i i
trap cleanup EXIT

# Ask user to select files #

while read -r file; do
    # file ID is SHA-256 digest as hex string
    file_id=$(sha256sum ${file} | cut -f1 -d" ")

    # device name as seen by lxc
    dev_name=mapped-${file_id}

    # path inside container
    container_path=/home/ubuntu/maps/${file_id:0:10}-$(basename "${file}")

    # keep track of original ACL so we can retore it later
    mapped_acls[${file_id}]=$(getfacl "${file}")

    # allow container to read and write with host
    setfacl --modify mask:rw,user:1001000:rw "${file}"

    lxc config device add \
      "${container}" \
      ${dev_name} \
      disk \
      source="${file}" \
      path="${container_path}"
    mapped_files[${file_id}]="${file}"
    mapped_devices[${file_id}]=${dev_name}
    mapped_container_paths[${file_id}]="${container_path}"
done < <(zenity --title="${WINDOW_TITLE} - Step 2 of 2: Select file(s)" --window-icon=question --file-selection --multiple --separator=$'\n')

[ ${#mapped_files[@]} -eq 0 ] && exit

# Show mapped files list until user allows them to be unmapped #

while true; do
    wait
    prompt_text=''
    if [ -n "$(list_xpra_sessions)" ]; then
        prompt_text='Detected a GUI session. Possible data loss. '
    fi
    prompt_text+="Unmap ${#mapped_files[@]} file(s) from container \"${container}\"?"
    zenity \
      --title="${WINDOW_TITLE}" \
      --question \
      --text="${prompt_text}" \
      --no-wrap \
      && break
done
