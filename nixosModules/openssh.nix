{ config, lib, ... }:
with lib;
mkMerge [
  (mkIf config.thoughtfull.impermanence.enable {
    environment.persistence."/persistent" = {
      files = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
      ];
    };
  })
  {
    services.openssh.hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
    systemd.services.sshd-keygen.enable = mkDefault false;
  }
]
