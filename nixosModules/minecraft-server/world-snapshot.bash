set -euo pipefail

data_dir="@dataDir@"
worlds="@worldDirs@"
persistent_dir="@persistentDir@"
snapshot_dir="@snapshotDir@"
snapshots_device="@snapshotsDevice@"
snapshots_subvol_name="@snapshotsSubvolName@"
max_age_seconds="@maxAgeSeconds@"
# Kept in dataDir (persists across reboots, same as the rest of the
# Minecraft data) rather than next to the snapshot itself: the snapshot can
# legitimately disappear on its own (see the refresh below), and the marker
# needs to survive that independently to still know how old the last refresh
# was.
marker="$data_dir/.last-world-snapshot"
mount_point="$data_dir/world.bak"
snapshot_name="$(basename "$snapshot_dir")"
rw_mount="/run/minecraft-world-snapshot-rw"
# The snapshot is a clone of the whole persistent subvolume, so the world
# dirs sit at the same path within it as they do under the live dataDir
# (dataDir is bind-mounted from persistentDir+dataDir -- see
# minecraft-server.nix).
snapshot_data_dir="$snapshot_dir$data_dir"

unmount_worlds() {
  # shellcheck disable=SC2086 # word splitting is intentional: worlds is a space-separated list
  for world in $worlds; do
    if mountpoint -q "$mount_point/$world" 2>/dev/null; then
      umount "$mount_point/$world"
    fi
  done
}

# btrfs snapshots are effectively instantaneous and don't disrupt the
# running server, so there's no need to time this for a quiet hour -- just
# refresh once the existing snapshot is more than max_age_seconds old, or
# it's missing entirely. Treating "missing" the same as "stale" makes this
# self-healing if the snapshot is ever gone for any other reason too (an
# interrupted refresh, a manual delete) -- recreating it here is just as
# cheap as the normal daily refresh.
now=$(date +%s)
refresh=true
if [ -f "$marker" ] && [ -d "$snapshot_dir" ]; then
  created=$(cat "$marker")
  age=$((now - created))
  if [ "$age" -lt "$max_age_seconds" ]; then
    refresh=false
  fi
fi

if "$refresh"; then
  # Unmount before deleting: btrfs won't delete a subvolume that's still
  # bind-mounted from elsewhere.
  unmount_worlds

  # The standard snapshot_dir mount is read-only. Refresh through a private,
  # separate read-write mount of the same underlying subvolume instead of
  # remounting the standard one rw and back -- see minecraft-server.nix for
  # why remounting isn't safe here.
  mkdir -p "$rw_mount"
  mount -o "subvol=/$snapshots_subvol_name" "$snapshots_device" "$rw_mount"
  cleanup_rw() {
    umount "$rw_mount" 2>/dev/null || true
  }
  trap cleanup_rw EXIT

  if [ -e "$rw_mount/$snapshot_name" ]; then
    btrfs subvolume delete "$rw_mount/$snapshot_name"
  fi
  btrfs subvolume snapshot -r "$persistent_dir" "$rw_mount/$snapshot_name"

  trap - EXIT
  umount "$rw_mount"

  date +%s >"$marker"
fi

# dataDir itself always exists (created at user-creation time, well before
# any world is ever generated), so if its path inside the snapshot isn't
# there, that's a permission or path problem, not "no world yet" -- fail
# loudly instead of silently mounting nothing.
if [ ! -d "$snapshot_data_dir" ]; then
  echo "error: $snapshot_data_dir not found or not readable in the snapshot" >&2
  exit 1
fi

# (Re-)establish any bind mounts that aren't already active. This alone
# recovers from a reboot: the snapshot itself is real on-disk data and
# survives one, only the bind mounts don't, so as long as it's still fresh
# there's no need to create a new one, just remount the existing one.
# shellcheck disable=SC2086 # word splitting is intentional: worlds is a space-separated list
for world in $worlds; do
  if [ -d "$snapshot_data_dir/$world" ]; then
    mkdir -p "$mount_point/$world"
    if ! mountpoint -q "$mount_point/$world" 2>/dev/null; then
      mount --bind "$snapshot_data_dir/$world" "$mount_point/$world"
    fi
  fi
done
