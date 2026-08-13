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

echo "world-snapshot: starting (mount_point=$mount_point snapshot_dir=$snapshot_dir)"

# world.bak itself (as opposed to the world subdirectories bind-mounted
# into it below, whose ownership and mode come from whatever ends up
# mounted there) is just an ordinary directory: mkdir -p would otherwise
# leave it root:root 0755 the first time something creates it, rather than
# matching the rest of dataDir. Cheap and idempotent, so just do it every
# run regardless of whether a refresh happens.
mkdir -p "$mount_point"
chown minecraft:minecraft "$mount_point"
chmod 0700 "$mount_point"
echo "world-snapshot: ensured $mount_point is minecraft:minecraft 0700"

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
  echo "world-snapshot: marker present (created=$created age=${age}s max_age_seconds=$max_age_seconds), snapshot_dir exists"
  if [ "$age" -lt "$max_age_seconds" ]; then
    refresh=false
  fi
else
  echo "world-snapshot: marker missing or snapshot_dir missing -- refresh required regardless of age"
fi

if "$refresh"; then
  echo "world-snapshot: rebuild branch -- snapshot is stale or missing, rebuilding"

  # The standard snapshot_dir mount is read-only. Refresh through a private,
  # separate read-write mount of the same underlying subvolume instead of
  # remounting the standard one rw and back -- see minecraft-server.nix for
  # why remounting isn't safe here.
  mkdir -p "$rw_mount"
  mount -o "subvol=/$snapshots_subvol_name" "$snapshots_device" "$rw_mount"
  echo "world-snapshot: mounted $snapshots_device (subvol=/$snapshots_subvol_name) at $rw_mount read-write"
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
    echo "world-snapshot: leftover $new_snapshot_name found from an interrupted attempt -- deleting it"
    btrfs subvolume delete "$rw_mount/$new_snapshot_name"
  else
    echo "world-snapshot: no leftover $new_snapshot_name -- nothing to clear"
  fi
  echo "world-snapshot: creating $rw_mount/$new_snapshot_name from $persistent_dir"
  btrfs subvolume snapshot -r "$persistent_dir" "$rw_mount/$new_snapshot_name"

  new_snapshot_data_dir="$rw_mount/$new_snapshot_name$data_dir"
  if [ ! -d "$new_snapshot_data_dir" ]; then
    echo "error: $new_snapshot_data_dir not found or not readable in the new snapshot" >&2
    exit 1
  fi
  echo "world-snapshot: new snapshot verified good at $new_snapshot_data_dir"

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
        echo "world-snapshot: $mount_point/$world already mounted -- unmounting before swap"
        umount "$mount_point/$world"
      else
        echo "world-snapshot: $mount_point/$world not currently mounted"
      fi
      mount --bind "$new_snapshot_data_dir/$world" "$mount_point/$world"
      echo "world-snapshot: mounted $mount_point/$world from the new snapshot"
    else
      echo "world-snapshot: $world not present in the new snapshot -- leaving $mount_point/$world alone"
    fi
  done

  # Nothing references the old subvolume anymore, so it's safe to delete
  # now (btrfs won't delete a subvolume that's still bind-mounted from
  # elsewhere, which is exactly why this comes after the swap above, not
  # before) and put the new one in its place.
  if [ -e "$rw_mount/$snapshot_name" ]; then
    echo "world-snapshot: deleting old snapshot $rw_mount/$snapshot_name"
    btrfs subvolume delete "$rw_mount/$snapshot_name"
  else
    echo "world-snapshot: no old snapshot to delete (first run)"
  fi
  mv "$rw_mount/$new_snapshot_name" "$rw_mount/$snapshot_name"
  echo "world-snapshot: renamed $new_snapshot_name to $snapshot_name"

  trap - EXIT
  umount "$rw_mount"
  echo "world-snapshot: unmounted $rw_mount"

  date +%s >"$marker"
  echo "world-snapshot: marker updated"
else
  echo "world-snapshot: still-fresh branch -- snapshot is still fresh, no rebuild needed"
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
# no-op on the refresh branch above, which already leaves every world
# mounted.
# shellcheck disable=SC2086 # word splitting is intentional: worlds is a space-separated list
for world in $worlds; do
  if [ -d "$snapshot_data_dir/$world" ]; then
    mkdir -p "$mount_point/$world"
    if ! mountpoint -q "$mount_point/$world" 2>/dev/null; then
      echo "world-snapshot: $mount_point/$world not mounted -- (re-)establishing"
      mount --bind "$snapshot_data_dir/$world" "$mount_point/$world"
    else
      echo "world-snapshot: $mount_point/$world already mounted -- nothing to do"
    fi
  else
    echo "world-snapshot: $world not present in the snapshot -- leaving $mount_point/$world alone"
  fi
done

echo "world-snapshot: done"
