#!/usr/bin/env bash
set -euo pipefail

test "$(id -u)" = 0
test "$(findmnt -n -o FSTYPE /)" = ext4

# Prevent logs and the random seed from being written back during capture.
journalctl --relinquish-var
systemctl stop systemd-random-seed.service

# Drop build dependencies while retaining the installed system's closure.
nix-store --gc --quiet
rm -rf /root/.ssh /root/.cache /var/log/* /nix/var/log/nix/*
rm -f /root/.*_history /etc/ssh/ssh_host_* /var/lib/dbus/machine-id \
  /var/lib/systemd/random-seed /var/lib/systemd/credential.secret

# Each instance generates fresh machine identity and SSH host keys on boot.
printf 'uninitialized\n' > /etc/machine-id
chmod 0444 /etc/machine-id

rm -rf /tmp/packer-* /tmp/script_*
rm -f -- "$0"
sync
echo 'Image generalized. OCI will shut down and capture the boot volume.'
