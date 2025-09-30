_self: {
  default =
    { ... }:
    {
      nix.extraOptions = ''
        experimental-features = nix-command flakes
      '';
      nixpkgs.config.allowUnfree = true;
    };
  dvorak = import ./dvorak.nix;
  fonts = import ./fonts.nix;
  technosophist = import ./technosophist.nix;
}
