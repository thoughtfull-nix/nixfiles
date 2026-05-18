{ config, lib, ... }:
let
  inherit (config.thoughtfull) graphical;
  inherit (lib) mkDefault;
in
{
  system.autoUpgrade = {
    # Daily upgrades are normally driven by `thoughtfull.systemPull`, which
    # pulls a pre-built, signed closure from the binary cache. This module
    # is kept in-tree as a fallback that individual hosts can opt back into
    # if the cache is unreachable for an extended period; see
    # `doc/binary-cache-runbook.md`.
    enable = mkDefault false;
    flake = mkDefault "github:thoughtfull-nix/nixfiles";
    dates = mkDefault (if graphical.enable then "*-*-* 12:00:00" else "*-*-* 03:00:00");
    randomizedDelaySec = mkDefault "15min";
    # Headless hosts may reboot for kernel updates; graphical hosts stage the
    # new kernel and apply it on the user's next manual reboot.
    allowReboot = mkDefault (!graphical.enable);
  };
}
