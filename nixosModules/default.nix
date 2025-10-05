{ inputs, ... }:
{
  default =
    { ... }:
    {
      imports = [
        ./impermanence.nix
        ./users.nix
        inputs.disko.nixosModules.default
        inputs.impermanence.nixosModules.impermanence
      ];
      nix.extraOptions = ''
        experimental-features = nix-command flakes
      '';
      nixpkgs.config.allowUnfree = true;
    };
  dvorak = import ./dvorak.nix;
  fonts = import ./fonts.nix;
}
