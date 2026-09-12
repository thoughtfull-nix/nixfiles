{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOverride
    ;
  cfg = config.thoughtfull.ec2;
in
{
  config = mkIf cfg.enable {
    # An EC2 instance boots from the amazon-image profile's own root filesystem
    # and bootloader, so this repo's physical-host machinery steps aside:
    # disko/LUKS/impermanence off (impermanence gates disko), and the bastion is
    # stateless so nothing to back up or sync. The systemd-boot + FIDO2-LUKS
    # boot block is gated off in boot.nix on thoughtfull.ec2.enable.
    thoughtfull.impermanence.enable = mkDefault false;
    services.restic.thoughtfull.enable = mkOverride 900 false;
    services.syncthing.enable = mkOverride 900 false;

    # binaryCache and system-pull are deliberately NOT disabled: supplying the
    # host's cache credentials auto-enables the daily system-pull, which is how
    # the bastion receives security updates.

    # Without impermanence, agenix.nix does not point the identity at a
    # /persistent path; decrypt secrets with the instance's own host key.
    age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # openssh.nix disables automatic host-key generation (physical hosts are
    # seeded with a key during bootstrap); a fresh cloud instance must generate
    # its own. mkOverride 900 to win over that mkDefault while still yielding to
    # a host override.
    systemd.services.sshd-keygen.enable = mkOverride 900 true;
  };

  options.thoughtfull.ec2.enable = mkEnableOption ''
    adjustments for running as a stateless AWS EC2 instance: no
    disko/LUKS/impermanence, no restic/syncthing, and host-key/agenix handling
    suited to a cloud image (system-pull is kept for security updates). Import
    the nixpkgs `virtualisation/amazon-image.nix` profile in the host config
    alongside enabling this
  '';
}
