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
    thoughtfull.impermanence.enable = mkDefault false;
    services.restic.thoughtfull.enable = mkOverride 900 false;
    services.syncthing.enable = mkOverride 900 false;
    # Without impermanence, agenix.nix does not point the identity at a
    # /persistent path; decrypt secrets with the instance's own host key.
    age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    systemd.services.sshd-keygen.enable = mkOverride 900 true;

    # The amazon-image ESP (/boot) is only ~250MB, and each aarch64 kernel +
    # initrd is ~85MB. system-pull creates a new generation daily and GRUB keeps
    # a kernel+initrd per generation there, so cap how many it keeps. During a
    # switch GRUB copies the new generation's files before pruning old ones, so
    # the transient peak is (limit + 1) generations: limit 1 peaks at ~170MB
    # (fits), limit 2 would peak at ~255MB (overflows).
    boot.loader.grub.configurationLimit = mkDefault 1;
  };

  options.thoughtfull.ec2.enable = mkEnableOption ''
    adjustments for running as a stateless AWS EC2 instance: no
    disko/LUKS/impermanence, no restic/syncthing, and host-key/agenix handling
    suited to a cloud image (system-pull is kept for security updates). Import
    the nixpkgs `virtualisation/amazon-image.nix` profile in the host config
    alongside enabling this
  '';
}
