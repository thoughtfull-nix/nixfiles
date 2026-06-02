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
      git.enable = mkDefault true;
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
    # mkOverride 900: win over openssh module's mkDefault (1000) but yield to
    # host configs using normal assignment (100) or mkForce (50)
    systemd.services.sshd-keygen.enable = mkOverride 900 true;
    thoughtfull = {
      # Installer images have no agenix-decrypted credentials, so disable
      # both the binary cache substituter (would fail to read S3) and the
      # daily system-pull timer (would fail to fetch the pointer file).
      # The installer evaluates the flake locally instead.
      binaryCache.enable = mkDefault false;
      impermanence.enable = mkDefault false;
      systemPull.enable = mkDefault false;
      user = {
        extraGroups = [ "wheel" ];
        name = mkDefault "technosophist";
        password = mkDefault "nixos";
      };
    };
  };
  options.thoughtfull.installer.enable = mkEnableOption "installer configuration";
}
