{ lib, pkgs, ... }:
let
  inherit (pkgs)
    makeDesktopItem
    symlinkJoin
    ;
  inherit (pkgs.lib) makeOverridable;
  inherit (lib) writeFileScriptBin;
in
makeOverridable
  (
    {
      bash,
      fuzzel,
      libnotify,
      wl-clipboard,
      yubikey-manager,
    }:
    let
      yubikey-totp-script = writeFileScriptBin {
        name = "yubikey-totp";
        replacements = {
          bash = "${bash}/bin/bash";
          fuzzel = "${fuzzel}/bin/fuzzel";
          notify_send = "${libnotify}/bin/notify-send";
          wl_copy = "${wl-clipboard}/bin/wl-copy";
          ykman = "${yubikey-manager}/bin/ykman";
        };
        src = ./yubikey-totp/yubikey-totp.bash;
      };
      yubikey-totp-desktop = makeDesktopItem {
        name = "yubikey-totp";
        desktopName = "Grab TOTP from Yubikey";
        exec = "${yubikey-totp-script}/bin/yubikey-totp";
        icon = "security-high";
        terminal = false;
        type = "Application";
        categories = [ "Utility" ];
      };
    in
    symlinkJoin {
      name = "yubikey-totp";
      paths = [
        yubikey-totp-script
        yubikey-totp-desktop
      ];
    }
  )
  {
    inherit (pkgs)
      bash
      fuzzel
      libnotify
      wl-clipboard
      yubikey-manager
      ;
  }
