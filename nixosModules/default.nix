{
  default = _: {
    imports = [
      ./users.nix
    ];
    nix.extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
  dvorak = import ./dvorak.nix;
  fonts = import ./fonts.nix;
}
