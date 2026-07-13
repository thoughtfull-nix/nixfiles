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
          # binaryCache.awsCredentialsFile = ./BOOTSTRAP/secrets/nix-cache-credentials.age;
          dev.enable = true;
          # Only needed for manual `nixos-rebuild` or installer/bootstrap flows that evaluate the
          # flake locally (see nixosModules/github-token.nix); run
          # `nixfiles secret encrypt BOOTSTRAP github-access-token` and uncomment once encrypted:
          # githubToken.tokenFile = ./BOOTSTRAP/secrets/github-access-token.age;
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
