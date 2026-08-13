set -euo pipefail

data_dir="@dataDir@"
worlds="@worldDirs@"
snapshot_dir="@snapshotDir@"
# The snapshot is a clone of the whole persistent subvolume, so the world
# dirs sit at the same path within it as they do under the live dataDir
# (dataDir is bind-mounted from persistentDir+dataDir -- see
# minecraft-server.nix).
snapshot_data_dir="$snapshot_dir$data_dir"
tmp="$data_dir/world.bak.tmp"

# dataDir itself always exists (created at user-creation time, well before
# any world is ever generated), so if its path inside the snapshot isn't
# there, that's not "no world yet" -- it's a permission or path problem (e.g.
# a parent directory missing the traversal bit for the minecraft user this
# script runs as). Fail loudly instead of silently shipping an empty
# world.bak: the per-world `[ -d ... ]` checks below can't tell "doesn't
# exist" from "exists but unreadable", so this is the one place that can.
if [ ! -d "$snapshot_data_dir" ]; then
  echo "error: $snapshot_data_dir not found or not readable in the snapshot" >&2
  exit 1
fi

# Start from a clean tmp dir in case a previous run was interrupted partway
# through the rsync loop below.
rm -rf "$tmp"
mkdir -p "$tmp"

# shellcheck disable=SC2086 # word splitting is intentional: worlds is a space-separated list
for world in $worlds; do
  if [ -d "$snapshot_data_dir/$world" ]; then
    rsync -a --delete "$snapshot_data_dir/$world/" "$tmp/$world/"
  fi
done

# Rename rather than copy in place, so restic (or anything else) never
# observes a half-written world.bak. mv is atomic here because tmp lives on
# the same filesystem as world.bak (both under dataDir).
rm -rf "$data_dir/world.bak"
mv "$tmp" "$data_dir/world.bak"
