{ inputs, ... }:
{
  modules = [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    (
      { ... }:
      {
        thoughtfull.installer.enable = true;
      }
    )
  ];
  system = "x86_64-linux";
}
