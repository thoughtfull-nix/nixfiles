{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOverride
    ;
  cfg = config.thoughtfull.installer;
in
{
  config = mkIf cfg.enable {
    environment.systemPackages =
      with pkgs;
      with pkgs.thoughtfull;
      with inputs.disko.packages.${pkgs.stdenv.hostPlatform.system};
      [
        curl
        disko
        jq
        nixfiles
        pins
        tmux
        uns
        unzip
        usbutils
      ];
    # set the hostname from dhcp (or default to "nixos")
    networking.hostName = mkDefault "";
    programs = {
      git = {
        enable = mkDefault true;
        config.user = {
          email = mkDefault "technosophist@thoughtfull.systems";
          signingkey = mkDefault "DF2034C6";
        };
      };
      zsh.enable = mkDefault true;
    };
    security = {
      # among other things, this is necessary to set the hostname from dhcp
      polkit.enable = mkDefault true;
      sudo.extraRules = [
        {
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
          groups = [ "wheel" ];
        }
      ];
    };
    services = {
      emacs.enable = mkDefault true;
      openssh.enable = mkDefault true;
      pcscd.enable = mkDefault true;
      xremap.enable = mkDefault true;
    };
    system.stateVersion = mkDefault lib.trivial.release;
    systemd.services.sshd-keygen.enable = mkOverride 900 true;
    thoughtfull = {
      impermanence.enable = mkDefault false;
      user = {
        extraGroups = [ "wheel" ];
        name = mkDefault "technosophist";
        password = mkDefault "nixos";
      };
    };
  };
  options.thoughtfull.installer.enable = mkEnableOption "installer configuration";
}
