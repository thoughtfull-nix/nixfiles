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
new_snapshot_name="$snapshot_name.new"
rw_mount="/run/minecraft-world-snapshot-rw"
# The snapshot is a clone of the whole persistent subvolume, so the world
# dirs sit at the same path within it as they do under the live dataDir
# (dataDir is bind-mounted from persistentDir+dataDir -- see
# minecraft-server.nix).
snapshot_data_dir="$snapshot_dir$data_dir"

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

  # Build and verify the replacement snapshot under a temporary name first,
  # entirely before touching any bind mount that's currently serving
  # world.bak. If this fails partway (ENOSPC, a transient btrfs error, the
  # old subvolume being busy), world.bak is untouched and keeps serving the
  # previous, still-valid snapshot -- it just stays stale rather than going
  # empty. A leftover new_snapshot_name from an interrupted previous attempt
  # is cleared before trying again.
  if [ -e "$rw_mount/$new_snapshot_name" ]; then
    btrfs subvolume delete "$rw_mount/$new_snapshot_name"
  fi
  btrfs subvolume snapshot -r "$persistent_dir" "$rw_mount/$new_snapshot_name"

  new_snapshot_data_dir="$rw_mount/$new_snapshot_name$data_dir"
  if [ ! -d "$new_snapshot_data_dir" ]; then
    echo "error: $new_snapshot_data_dir not found or not readable in the new snapshot" >&2
    exit 1
  fi

  # Only now, with the replacement verified good, swap world.bak over to it.
  # A bind mount keeps working even after its source is renamed or its
  # source mount goes away entirely (it references the underlying data, not
  # the live path used to reach it), so the mv and the later umount below
  # don't disturb these once they're established. mount --bind of an
  # already-existing, already-verified directory also has essentially none
  # of the failure modes the snapshot creation above does, so this is a much
  # narrower risk window than unmounting world.bak before the snapshot work
  # ever was.
  # shellcheck disable=SC2086 # word splitting is intentional: worlds is a space-separated list
  for world in $worlds; do
    if [ -d "$new_snapshot_data_dir/$world" ]; then
      mkdir -p "$mount_point/$world"
      if mountpoint -q "$mount_point/$world" 2>/dev/null; then
        umount "$mount_point/$world"
      fi
      mount --bind "$new_snapshot_data_dir/$world" "$mount_point/$world"
    fi
  done

  # Nothing references the old subvolume anymore, so it's safe to delete
  # now (btrfs won't delete a subvolume that's still bind-mounted from
  # elsewhere, which is exactly why this comes after the swap above, not
  # before) and put the new one in its place.
  if [ -e "$rw_mount/$snapshot_name" ]; then
    btrfs subvolume delete "$rw_mount/$snapshot_name"
  fi
  mv "$rw_mount/$new_snapshot_name" "$rw_mount/$snapshot_name"

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
# there's no need to create a new one, just remount the existing one. A
# no-op on the path just above, which already leaves every world mounted.
# shellcheck disable=SC2086 # word splitting is intentional: worlds is a space-separated list
for world in $worlds; do
  if [ -d "$snapshot_data_dir/$world" ]; then
    mkdir -p "$mount_point/$world"
    if ! mountpoint -q "$mount_point/$world" 2>/dev/null; then
      mount --bind "$snapshot_data_dir/$world" "$mount_point/$world"
    fi
  fi
done
