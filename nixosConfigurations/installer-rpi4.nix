{ inputs, ... }:
{
  modules = [
    "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    (
      { ... }:
      {
        hardware.raspberry-pi."4".poe-hat.enable = true;
        thoughtfull = {
          installer.enable = true;
          rpi4.enable = true;
        };
      }
    )
  ];
  system = "aarch64-linux";
}
