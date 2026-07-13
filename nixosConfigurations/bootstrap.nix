{ ... }:
{
  modules = [
    (
      { ... }:
      {
        imports = [
          ./BOOTSTRAP/hardware-configuration.nix
        ];
        networking.hostName = "BOOTSTRAP";
        services.syncthing.thoughtfull.passwordFile = ./BOOTSTRAP/secrets/syncthing-passphrase.age;
        system.stateVersion = "25.11";
        thoughtfull = {
          # Create an IAM user + key for BOOTSTRAP and uncomment once encrypted (see
          # doc/binary-cache-runbook.md section 2):
          # binaryCache.awsCredentialsFile = ./BOOTSTRAP/secrets/nix-cache-host-credentials.age;
          dev.enable = true;
          graphical.enable = true;
          impermanence.disko = {
            # boot.size = "1G";
            # encrypted.device = "/dev/nvme0n1";
            # swap.size = "4G";
          };
          user.hashedPasswordFile = ./BOOTSTRAP/secrets/hashed-user-passphrase.age;
        };
      }
    )
  ];
  system = "x86_64-linux";
}
