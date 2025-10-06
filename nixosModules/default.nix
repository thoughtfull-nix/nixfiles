{ ... }:
{
  default =
    { ... }:
    {
      imports = [
        ./users.nix
      ];
      nix.extraOptions = ''
        experimental-features = nix-command flakes
      '';
      nixpkgs.config.allowUnfree = true;
    };
  dvorak = import ./dvorak.nix;
  fonts = import ./fonts.nix;
}
