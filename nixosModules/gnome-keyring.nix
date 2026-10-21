{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) sway;
  inherit (lib)
    concatStringsSep
    mkDefault
    mkIf
    mkOption
    types
    ;
  inherit (pkgs) bash;
  inherit (pkgs.thoughtfull) writeFileScript;
  cfg = config.services.gnome.gnome-keyring;
  unlock = writeFileScript {
    name = "gnome-keyring-unlock";
    replacements.bash = "${bash}/bin/bash";
    src = ./gnome-keyring/unlock.bash;
  };
in
{
  config = mkIf cfg.enable {
    thoughtfull.impermanence.user.directories = mkIf sway.enable [
      {
        directory = ".local/share/keyrings";
        mode = "0700";
      }
    ];
    systemd.user.services.gnome-keyring-unlock = {
      description = "Unlock the login keyring with a FIDO2 key";
      after = [ "sway-session.target" ];
      partOf = [ "sway-session.target" ];
      enable = mkDefault (sway.enable && cfg.thoughtfull.fido2Recipients != [ ]);
      wantedBy = [ "sway-session.target" ];
      # A rebuild-switch shouldn't prompt for the PIN mid-session.
      restartIfChanged = mkDefault false;
      environment.KEYRING_RECIPIENTS = concatStringsSep " " cfg.thoughtfull.fido2Recipients;
      path = with pkgs; [
        age-plugin-fido2-hmac
        libnotify
        pinentry-gtk2
        rage
        socat
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${unlock}";
      };
    };
  };
  options.services.gnome.gnome-keyring.thoughtfull.fido2Recipients = mkOption {
    default = [ ];
    description = ''
      age-plugin-fido2-hmac recipients (from `age-plugin-fido2-hmac -g`). When
      set, a sway login unlocks the login keyring with a random password
      age-encrypted to them, prompting for the FIDO2 PIN and a touch.
    '';
    type = types.listOf types.str;
  };
}
