{ config, lib, ... }:
let
  cfg = config.environment.persistence;
  fsCfg = config.fileSystems;
in
{
  boot.initrd.postResumeCommands =
    lib.mkIf
      (
        cfg ? "/persistence"
        && cfg."/persistence".enable
        && fsCfg ? "/persistence"
        && fsCfg."/persistence".enable
      )
      (
        lib.mkAfter ''
          # move root to a new snapshot
          mkdir /btrfs_tmp
          mount ${fsCfg."/persistence".device} /btrfs_tmp
          if [[ -e /btrfs_tmp/root ]]; then
            mkdir -p /btrfs_tmp/old_roots
            timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%FT%T")
            mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
          fi

          delete_subvolume_recursively() {
            IFS=$'\n'
            for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
            done
            btrfs subvolume delete "$1"
          }

          # delete snapshots older than 30 days
          for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
            delete_subvolume_recursively "$i"
          done

          # create new empty subvolume
          btrfs subvolume create /btrfs_tmp/root
          umount /btrfs_tmp
        ''
      );
}
