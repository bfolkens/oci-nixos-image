#!/usr/bin/env bash
set -euo pipefail

test "$(id -u)" = 0
test "$(uname -m)" = aarch64
# cloud-init can finish successfully enough to bootstrap while reporting
# recoverable errors (exit 2). Keep diagnostics visible and reject other failures.
cloud_init_status=0
cloud-init status --wait --long || cloud_init_status=$?
case "$cloud_init_status" in
  0) ;;
  2)
    echo 'cloud-init completed with recoverable errors; printing log excerpts.' >&2
    echo 'cloud-init schema validation:'
    cloud-init schema --system || true
    for log_file in /var/log/cloud-init.log /var/log/cloud-init-output.log; do
      printf '\ncloud-init log excerpt: %s (up to 80 lines, 500 characters per line)\n' "$log_file"
      if [[ ! -r "$log_file" ]]; then
        echo 'Log unavailable or not readable.'
        continue
      fi

      # Match actual log severities; DEBUG discovery retries can contain "failed"
      # or "exception" even when networking recovers normally.
      # Keep context around recent failures without flooding Packer's output.
      # Diagnostic failures must not stop an otherwise recoverable bootstrap.
      if log_excerpt=$(grep -nEi -C 3 '\[(warn(ing)?|error|critical|fatal)\]|^[[:space:]]*(warn(ing)?|error|critical|fatal|traceback)([[:space:]:]|$)' "$log_file" | tail -n 80 | cut -c 1-500); then
        printf '%s\n' "$log_excerpt"
      else
        echo 'No matching entries, or filtering failed; showing recent log output:'
        tail -n 20 "$log_file" | cut -c 1-500 || true
      fi
    done
    echo 'Continuing bootstrap after recoverable cloud-init errors.'
    ;;
  *)
    echo "cloud-init failed (exit $cloud_init_status); stopping bootstrap." >&2
    exit "$cloud_init_status"
    ;;
esac

archive=/root/nixos-kexec-installer.tar.gz
curl --fail --location --retry 3 --output "$archive" "$KEXEC_INSTALLER_URL"
printf '%s  %s\n' "$KEXEC_INSTALLER_SHA256" "$archive" | sha256sum --check --strict
tar -xzf "$archive" -C /root
rm -f "$archive"

# Keep the runner's SSH and network setup and kernel load. Let systemd shut
# down services and unmount filesystems before handing off to the new kernel.
runner=/root/kexec/run
if ! grep -Fxq '# Disconnect our background kexec from the terminal' "$runner"; then
  echo 'Unrecognized installer runner. Review the kexec handoff before changing the installer archive.' >&2
  exit 1
fi
sed -i '/^# Disconnect our background kexec from the terminal$/,$d' "$runner"
"$runner"
if [[ $(cat /sys/kernel/kexec_loaded) != 1 ]]; then
  echo 'The installer kernel was not loaded.' >&2
  exit 1
fi
echo 'Handing off to the NixOS installer through systemd.'
systemctl --no-block kexec
