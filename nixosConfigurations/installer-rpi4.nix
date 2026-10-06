{ inputs, ... }:
{
  modules = [
    "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    (
      { ... }:
      {
        boot.initrd = {
          allowMissingModules = true;
          network.ssh.enable = false;
        };
        thoughtfull = {
          installer.enable = true;
          rpi4 = {
            enable = true;
            poeHat.enable = true;
          };
        };
      }
    )
  ];
  system = "aarch64-linux";
}
