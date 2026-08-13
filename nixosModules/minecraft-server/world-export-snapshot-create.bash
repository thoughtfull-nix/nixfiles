set -euo pipefail

snapshot_dir="@snapshotDir@"
persistent_dir="@persistentDir@"

# No-op in production, where the snapshots subvolume is already mounted;
# needed for the test setup, which nests the snapshot destination inside a
# plain directory instead of standing up a second subvolume.
mkdir -p "$(dirname "$snapshot_dir")"

# Clean up a stale snapshot left behind by an interrupted previous run before
# creating a fresh one.
if [ -e "$snapshot_dir" ]; then
  btrfs subvolume delete "$snapshot_dir"
fi
btrfs subvolume snapshot -r "$persistent_dir" "$snapshot_dir"
