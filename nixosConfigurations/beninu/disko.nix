_: {
  disko.devices.disk.main = {
    content = {
      partitions = {
        ESP = {
          content = {
            format = "vfat";
            mountOptions = [ "umask=0077" ];
            mountpoint = "/boot";
            type = "filesystem";
          };
          size = "512M";
          type = "EF00";
        };
        luks = {
          content = {
            content = {
              extraArgs = [ "-f" ];
              subvolumes = {
                "/nix" = {
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                  mountpoint = "/nix";
                };
                "/persistent" = {
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                  mountpoint = "/persistent";
                };
                "/root" = {
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                  mountpoint = "/";
                };
                "/swap" = {
                  mountpoint = "/.swapvol";
                  swap.swapfile.size = "4G";
                };
              };
              type = "btrfs";
            };
            name = "encrypted";
            settings = {
              allowDiscards = true;
            };
            type = "luks";
          };
          size = "100%";
        };
      };
      type = "gpt";
    };
    device = "/dev/sda";
    type = "disk";
  };
}
