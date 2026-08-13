set -euo pipefail

snapshot_dir="@snapshotDir@"

if [ -e "$snapshot_dir" ]; then
  btrfs subvolume delete "$snapshot_dir"
fi
