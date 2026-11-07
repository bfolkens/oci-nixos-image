#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
. /etc/os-release
test "$ID" = nixos
test "$(id -u)" = 0
test "$(uname -m)" = aarch64

# Refuse to partition unless this is the RAM installer, never an installed root.
if [[ "$(findmnt -n -o FSTYPE /)" != tmpfs ]]; then
  echo 'Refusing to partition: root is not the temporary installer tmpfs.' >&2
  exit 1
fi
test -b /dev/sda
test -d /sys/firmware/efi

image_dir=/tmp/nixos-image
test -s "$image_dir/flake.lock"
export NIX_CONFIG='experimental-features = nix-command flakes'

# Both NixOS and disko are pinned by the uploaded lock file.
nix run --no-write-lock-file "path:$image_dir#disko" -- \
  --mode destroy,format,mount --yes-wipe-all-disks "$image_dir/files/disk-config.nix"
findmnt --target /mnt
findmnt --target /mnt/boot

install -d -m 0755 /mnt/etc/nixos
# Retain the rebuild configuration, not the installer-only disk layout.
cp "$image_dir/flake.nix" "$image_dir/flake.lock" /mnt/etc/nixos/
cp -a "$image_dir/modules" /mnt/etc/nixos/
nixos-install --no-root-passwd --no-channel-copy --flake path:/mnt/etc/nixos#oci-base
sync
echo 'NixOS installed. Packer will now reboot from the boot volume.'
