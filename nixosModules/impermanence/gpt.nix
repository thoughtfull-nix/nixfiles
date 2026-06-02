{ config, lib, ... }:
let
  inherit (config.thoughtfull) impermanence;
  inherit (lib) mkIf;
  persistentName = impermanence.persistent.name;
  snapshotsName = impermanence.snapshots.name;
  encryptedName = impermanence.encrypted.name;
  inherit (impermanence.disko)
    boot
    enable
    encrypted
    nix
    persistent
    root
    snapshots
    swap
  ;
in
{
  config = {
    assertions = [
      {
        assertion = !enable || encrypted.device != null;
        message = "thoughtfull.impermanence.disko.encrypted.device is not configured";
      }
    ];
    disko.devices.disk.main = mkIf enable {
      content = {
        partitions = {
          ESP = {
            content = {
              format = "vfat";
              mountOptions = boot.mountOptions;
              mountpoint = "/boot";
              type = "filesystem";
            };
            size = boot.size;
            type = "EF00";
          };
          luks = {
            content = {
              content = {
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/nix" = {
                    mountOptions = nix.mountOptions;
                    mountpoint = "/nix";
                  };
                  "/${persistentName}" = {
                    mountOptions = persistent.mountOptions;
                    mountpoint = persistent.mountPoint;
                  };
                  "/${root.name}" = {
                    mountOptions = root.mountOptions;
                    mountpoint = "/";
                  };
                  "/${snapshotsName}" = {
                    mountOptions = snapshots.mountOptions;
                    mountpoint = snapshots.mountPoint;
                  };
                  "/swap" = {
                    mountpoint = "/.swapvol";
                    swap.swapfile.size = swap.size;
                  };
                };
                type = "btrfs";
              };
              name = encryptedName;
              passwordFile = "/tmp/luks-recovery-passphrase.txt";
              settings.allowDiscards = true;
              type = "luks";
            };
            size = "100%";
          };
        };
        type = "gpt";
      };
      device = encrypted.device;
      type = "disk";
    };
  };
}
