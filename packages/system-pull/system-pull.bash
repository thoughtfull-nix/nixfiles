#!@bash@
set -euo pipefail

# Pull the latest signed system closure for this host from the S3 binary
# cache and switch to it. Intended to run as root from a systemd timer, but
# also runnable by hand with sudo. Takes no arguments: the bucket, region, and
# credentials-file path are baked in at build time by the system-pull module.
#
# The credentials file is an agenix-decrypted EnvironmentFile (KEY=value)
# holding this host's read-only AWS credentials. It is loaded, via dotenvy,
# into the environment of only the two commands that reach the S3 cache -- the
# pointer fetch and the closure realise -- so the credentials never reach
# switch-to-configuration or the activation scripts it runs. dotenvy parses the
# file rather than sourcing it; note it expands $VAR references (systemd's
# EnvironmentFile does not), which is harmless for base64 AWS keys. The file is
# root-only, so an unprivileged run fails at the fetch.
#
# The realise needs the credentials directly: system-pull runs as root, whose
# `auto` store realises in-process rather than through nix-daemon, so
# `nix-store --realise` substitutes from the S3 cache in this process and the
# daemon's own EnvironmentFile (see binary-cache.nix) does not apply to it.

bucket="@bucket@"
region="@region@"
creds_file="@credentials_file@"
hostname=$(@hostname@)

pointer_url="s3://${bucket}/hosts/${hostname}/latest.json"
echo "system-pull: fetching ${pointer_url}"

pointer=$(@dotenvy@ -f "${creds_file}" @aws@ s3 cp "${pointer_url}" - --region "${region}")
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
@dotenvy@ -f "${creds_file}" @nix_store@ --realise "${target}"

echo "system-pull: registering system profile generation"
@nix_env@ -p /nix/var/nix/profiles/system --set "${target}"

echo "system-pull: switching configuration"
# Run switch-to-configuration directly, in-process, so its output is captured
# in system-pull.service's own journal. This relies on the service being
# shielded from activation stopping it out from under the switch: a stable
# ExecStart (/run/current-system/sw/bin/system-pull) keeps the unit
# byte-identical across generations (so it isn't restarted), restartIfChanged
# skips it if it does change, and X-StopOnRemoval=false keeps it running if a
# generation removes it.
"${target}/bin/switch-to-configuration" switch

echo "system-pull: switched to ${target}"

echo "system-pull: collecting garbage (generations older than @gc_delete_older_than@)"
# Run GC here, synchronously after a successful switch, rather than via an
# independent nix.gc.automatic timer: sequencing it inside this oneshot means
# no GC run can ever land during the realise -> nix-env --set window above,
# where the freshly fetched closure is briefly unrooted, and old generations
# are only deleted once the new one has proven it activates.
@nix_collect_garbage@ --delete-older-than @gc_delete_older_than@

echo "system-pull: reinstalling boot loader to prune entries for deleted generations"
# nix-collect-garbage doesn't touch boot loader entries, so the menu still
# lists the generations just deleted above. Re-running switch-to-configuration
# with the `boot` action (rather than `switch`) reinstalls the boot loader
# from the generations still present and then exits immediately -- it does
# not repeat activation or restart anything -- so this is cheap.
"${target}/bin/switch-to-configuration" boot
