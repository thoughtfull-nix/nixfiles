{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkDefault mkEnableOption mkIf;
in
{
  config = mkIf config.thoughtfull.yubikey.enable {
    environment.systemPackages = with pkgs; [
      age-plugin-yubikey
      yubioath-flutter
    ];
    hardware.gpgSmartcards.enable = mkDefault true;
    programs.yubikey-manager.enable = mkDefault true;
    services.pcscd.enable = mkDefault true;
    security.pam.u2f = {
      enable = mkDefault true;
      settings = {
        appid = mkDefault "pam://auth";
        authfile = mkDefault "/etc/u2f-mappings";
        cue = mkDefault true;
        origin = mkDefault "pam://auth";
      };
    };
  };
  options.thoughtfull.yubikey.enable = mkEnableOption "yubikey" // {
    default = true;
  };
}
