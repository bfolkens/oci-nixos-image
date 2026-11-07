#!/usr/bin/env bash
set -euo pipefail

keys_file=$(mktemp "$RUNTIME_DIRECTORY/.keys.XXXXXX")
trap 'rm -f "$keys_file"' EXIT

curl --fail --silent --show-error --noproxy '*' \
  --connect-timeout 5 --max-time 10 \
  --retry 12 --retry-delay 3 --retry-max-time 120 --retry-all-errors \
  --header 'Authorization: Bearer Oracle' \
  --output "$keys_file" \
  http://169.254.169.254/opc/v2/instance/metadata/ssh_authorized_keys

# Reject empty/error responses before replacing the authorized key file.
test -s "$keys_file"
ssh-keygen -l -f "$keys_file" >/dev/null
chmod 0600 "$keys_file"
mv -f "$keys_file" "$RUNTIME_DIRECTORY/root"
