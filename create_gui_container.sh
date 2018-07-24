#!/bin/bash
#
# Create a LXD Ubuntu container and profile (if necessary) to run GUI apps. Then
# start it with any needed configuration.

# directory on host where bind mounts are created
readonly CONTAINER_MOUNTS_DIR=${HOME}/container_mounts

readonly JQ_CMD="jq -rM"

function usage() {
  echo "$(basename $0) container-name authorized-keys-file lxd-profile-base-file clound-init-file..."
  echo
}

function print_status() {
  echo "[+] $*"
}

function print_err() {
  echo "[!] $*"
}

# XXX: hack until we convert this whole shell script to Python
function write_mime_multipart() {
python - "$@" <<EOF
#!/usr/bin/python3
# http://bazaar.launchpad.net/~cloud-utils-dev/cloud-utils/trunk/view/head:/bin/write-mime-multipart
#
# largely taken from python examples
# http://docs.python.org/library/email-examples.html

import os
import sys

from email import encoders
from email.mime.base import MIMEBase
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from optparse import OptionParser
import gzip

COMMASPACE = ', '

starts_with_mappings = {
    '#include': 'text/x-include-url',
    '#include-once': 'text/x-include-once-url',
    '#!': 'text/x-shellscript',
    '#cloud-config': 'text/cloud-config',
    '#cloud-config-archive': 'text/cloud-config-archive',
    '#upstart-job': 'text/upstart-job',
    '#part-handler': 'text/part-handler',
    '#cloud-boothook': 'text/cloud-boothook'
}


def try_decode(data):
    try:
        return (True, data.decode())
    except UnicodeDecodeError:
        return (False, data)


def get_type(fname, deftype):
    rtype = deftype

    with open(fname, "rb") as f:
        (can_be_decoded, line) = try_decode(f.readline())

    if can_be_decoded:
        # slist is sorted longest first
        slist = sorted(list(starts_with_mappings.keys()),
                       key=lambda e: 0 - len(e))
        for sstr in slist:
            if line.startswith(sstr):
                rtype = starts_with_mappings[sstr]
                break
    else:
        rtype = 'application/octet-stream'

    return(rtype)


def main():
    outer = MIMEMultipart()
    parser = OptionParser()

    parser.add_option("-o", "--output", dest="output",
                      help="write output to FILE [default %default]",
                      metavar="FILE", default="-")
    parser.add_option("-z", "--gzip", dest="compress", action="store_true",
                      help="compress output", default=False)
    parser.add_option("-d", "--default", dest="deftype",
                      help="default mime type [default %default]",
                      default="text/plain")
    parser.add_option("--delim", dest="delim",
                      help="delimiter [default %default]", default=":")

    (options, args) = parser.parse_args()

    if (len(args)) < 1:
        parser.error("Must give file list see '--help'")

    for arg in args:
        t = arg.split(options.delim, 1)
        path = t[0]
        if len(t) > 1:
            mtype = t[1]
        else:
            mtype = get_type(path, options.deftype)

        maintype, subtype = mtype.split('/', 1)
        if maintype == 'text':
            fp = open(path)
            # Note: we should handle calculating the charset
            msg = MIMEText(fp.read(), _subtype=subtype)
            fp.close()
        else:
            fp = open(path, 'rb')
            msg = MIMEBase(maintype, subtype)
            msg.set_payload(fp.read())
            fp.close()
            # Encode the payload using Base64
            encoders.encode_base64(msg)

        # Set the filename parameter
        msg.add_header('Content-Disposition', 'attachment',
                       filename=os.path.basename(path))

        outer.attach(msg)

    if options.output is "-":
        if hasattr(sys.stdout, "buffer"):
            # We want to write bytes not strings
            ofile = sys.stdout.buffer
        else:
            ofile = sys.stdout
    else:
        ofile = open(options.output, "wb")

    if options.compress:
        gfile = gzip.GzipFile(fileobj=ofile, filename=options.output)
        gfile.write(outer.as_string().encode())
        gfile.close()
    else:
        ofile.write(outer.as_string().encode())

    ofile.close()

if __name__ == '__main__':
    main()

# vi: ts=4 expandtab
EOF
}

if [ $# -lt 4 ]; then
  usage
  exit 1
fi

readonly CONTAINER_NAME=$1
shift
readonly AUTHORIZED_KEYS_FILE=$1
shift
readonly LXD_PROFILE_BASE_FILE=$1
shift
readonly CLOUD_INIT_FILES="$*"
shift

# Check commandline args #

# check for SSH private keys
if grep -q 'PRIVATE' "${AUTHORIZED_KEYS_FILE}"; then
  read -r -p 'Detected possible private key in SSH authorized keys file. Continue using this file? [y|n]'
  [[ "${REPLY,,}" != "y" ]] && exit
fi

# name of profile to use
readonly PROFILE_NAME="${CONTAINER_NAME}"

# Create profile #

if lxc profile show "${PROFILE_NAME}" 2>/dev/null; then
  echo
  print_status "Profile \"${PROFILE_NAME}\" already exists. See above."
  read -r -p 'Continue with existing profile? [y|n]'
  [[ "${REPLY,,}" != "y" ]] && exit
else
  lxc profile create "${PROFILE_NAME}"

  print_status "Populating profile with base configuration."
  lxc profile edit "${PROFILE_NAME}" < "${LXD_PROFILE_BASE_FILE}"

  print_status "Adding user-data to profile."
  lxc profile set "${PROFILE_NAME}" user.user-data "$(write_mime_multipart ${CLOUD_INIT_FILES})"
fi

# Configure bind mounts #

# set all perms for group so we can use ACLs
mkdir -pm 771 "${CONTAINER_MOUNTS_DIR}"
setfacl \
  --modify default:user:1001000:rwx,default:user:"${USER}":rwx,default:mask:rwx \
  "${CONTAINER_MOUNTS_DIR}"

readonly mount_dir="${CONTAINER_MOUNTS_DIR}/${CONTAINER_NAME}"
print_status "Creating host directory for bind mount sources: \"${mount_dir}\""
mkdir -m 771 "${mount_dir}" || exit 1

# Create xpra bind mount #

readonly xpra_dir="${mount_dir}/xpra"
print_status "Creating host directory for storing xpra files the client might\
 need: \"${xpra_dir}\""
mkdir -m 771 "${xpra_dir}" || exit 1

# Create file sharing bind mount #

# Set up host share directory to allow container user to access host files and
# vice versa. Permissions are set using POSIX ACLs. We do this here after
# container launch because there is an timing issue which would result in LXD
# creating the container user's home directory with root ownership. The directory
# didn't exist when LXD was adding the share and did so by a root process.
readonly share_dir="${mount_dir}/share"
print_status "Creating host directory for file sharing between host and\
 container: \"${share_dir}\""
mkdir -m 771 "${share_dir}" || exit 1

# Start container #

print_status "Launching container."
lxc launch --profile default --profile "${PROFILE_NAME}" ubuntu: "${CONTAINER_NAME}" || exit 1

print_status "Waiting for cloud-init to complete in container."
lxc exec "${CONTAINER_NAME}" -- cloud-init status --wait || exit 1

print_status "Adding xpra bind mount to container config."
lxc \
  config device add "${CONTAINER_NAME}" xpra disk \
  path=/home/ubuntu/.xpra \
  source="${xpra_dir}" || exit 1

print_status "Adding file sharing bind mount to container config."
lxc \
  config device add "${CONTAINER_NAME}" share disk \
  path=/home/ubuntu/share \
  source="${share_dir}" || exit 1

# Configure SSH access #

print_status "Copying SSH authorized keys file to container."
lxc file push \
 "${AUTHORIZED_KEYS_FILE}" \
 "${CONTAINER_NAME}"/home/ubuntu/.ssh/authorized_keys || exit 1
readonly container_ip="$(lxc list --format json "${CONTAINER_NAME}" \
  | ${JQ_CMD} '.[].state.network.eth0.addresses[] | select(.family == "inet").address')"
# allow user to add server's host key to known hosts file
print_status "Testing SSH connection to container."
ssh -T ubuntu@"${container_ip}" exit

print_status "Restarting container so cloud-init boot script(s) run."
lxc restart "${CONTAINER_NAME}"
print_status "Waiting for cloud-init to complete in container."
lxc exec "${CONTAINER_NAME}" -- cloud-init status --wait || exit 1
