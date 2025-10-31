{
  default =
    { inputs, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.git ];
      imports = [
        ./impermanence.nix
        ./openssh.nix
        ./users.nix
        inputs.disko.nixosModules.default
        inputs.impermanence.nixosModules.impermanence
      ];
      nix.extraOptions = ''
        experimental-features = nix-command flakes
      '';
    };
  dvorak = import ./dvorak.nix;
  fonts = import ./fonts.nix;
}
