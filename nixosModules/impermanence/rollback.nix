{
  config,
  lib,
  pkgs,
}:
let
  inherit (lib) mkIf mkMerge;
  inherit (pkgs.thoughtfull) replaceVarsString;
  impermanence = config.thoughtfull.impermanence;
  rollback = replaceVarsString ./rollback.bash {
    device = "/dev/mapper/${impermanence.encrypted.name}";
    snapshots = impermanence.snapshots.name;
  };
  systemdEnabled = config.boot.initrd.systemd.enable;
in
{
  boot.initrd = mkMerge [
    (mkIf systemdEnabled {
      systemd.services.rollback = {
        description = "Rollback BTRFS root subvolume to a pristine state";
        wantedBy = [
          "initrd.target"
        ];
        after = [
          "basic.target"
        ];
        before = [
          "sysroot.mount"
        ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        ## systemd runs as bash with set -e
        ## systemd environment
        # MEMORY_PRESSURE_WRITE=c29tZSAyMDAwMDAgMjAwMDAwMAA=
        # PWD=/
        # SYSTEMD_EXEC_PID=269
        # LANG=C.UTF-8
        # MEMORY_PRESSURE_WATCH=/sys/fs/cgroup/system.slice/rollback.service/memory.pressure
        # INVOCATION_ID=55631cef4d0046d99b30092ce4275d95
        # USER=root
        # TZDIR=/nix/store/2s4hpq73hn49jd84x976m3acp3rd3k1x-tzdata-2025b/share/zoneinfo
        # SHLVL=1
        # LOCALE_ARCHIVE=/nix/store/qdlks9irhx3mn4r287hh1lmpblgp9szw-glibc-locales-2.40-66/lib/locale/locale-archive
        # JOURNAL_STREAM=9:6418
        # PATH=/bin:/sbin
        # _=/bin/env
        script = rollback;
      };
    })
    (mkIf (!systemdEnabled) {
      postResumeCommands = rollback;
    })
  ];
}
