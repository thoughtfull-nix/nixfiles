#!@bash@
set -euo pipefail

# Pull the latest signed system closure for this host from the S3 binary
# cache and switch to it. Intended to run as root from a systemd timer.
#
# Usage: system-pull <bucket> <region>
#
# Reads AWS credentials from the environment (the systemd unit sets
# EnvironmentFile to the agenix-decrypted credentials file). Falls back to
# the early exit if /run/current-system already points at the target.

if [[ $# -ne 2 ]]; then
  echo "usage: system-pull <bucket> <region>" >&2
  exit 64
fi

bucket=$1
region=$2
hostname=$(@hostname@)

pointer_url="s3://${bucket}/hosts/${hostname}/latest.json"
echo "system-pull: fetching ${pointer_url}"

pointer=$(@aws@ s3 cp "${pointer_url}" - --region "${region}")
target=$(printf '%s\n' "${pointer}" | @jq@ -r '.storePath')

if [[ -z ${target} || ${target} == "null" ]]; then
  echo "system-pull: pointer file did not contain a storePath" >&2
  echo "${pointer}" >&2
  exit 1
fi

current=$(@readlink@ /run/current-system)
if [[ ${target} == "${current}" ]]; then
  echo "system-pull: already at ${target}"
  exit 0
fi

echo "system-pull: realising ${target}"
@nix_store@ --realise "${target}"

echo "system-pull: registering system profile generation"
@nix_env@ -p /nix/var/nix/profiles/system --set "${target}"

echo "system-pull: switching configuration"
# Run switch-to-configuration in a transient unit so the switch survives
# activation-time stop/restart of system-pull.service itself.
@systemd_run@ \
  -E LOCALE_ARCHIVE \
  --collect \
  --no-ask-password \
  --pipe \
  --quiet \
  --service-type=exec \
  --unit=system-pull-switch-to-configuration \
  -- \
  "${target}/bin/switch-to-configuration" switch

echo "system-pull: switched to ${target}"
