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
      jq,
      libnotify,
      udisks2,
      util-linux,
    }:
    let
      replacements = {
        bash = "${bash}/bin/bash";
        fuzzel = "${fuzzel}/bin/fuzzel";
        jq = "${jq}/bin/jq";
        lsblk = "${util-linux}/bin/lsblk";
        notify_send = "${libnotify}/bin/notify-send";
        udisksctl = "${udisks2}/bin/udisksctl";
      };

      usb-mount-script = writeFileScriptBin {
        name = "usb-mount";
        inherit replacements;
        src = ./usb-menu/usb-mount.bash;
      };
      usb-mount-desktop = makeDesktopItem {
        name = "usb-mount";
        desktopName = "Mount USB drive";
        exec = "${usb-mount-script}/bin/usb-mount";
        icon = "drive-removable-media";
        terminal = false;
        type = "Application";
        categories = [ "Utility" ];
      };

      usb-unmount-script = writeFileScriptBin {
        name = "usb-unmount";
        inherit replacements;
        src = ./usb-menu/usb-unmount.bash;
      };
      usb-unmount-desktop = makeDesktopItem {
        name = "usb-unmount";
        desktopName = "Unmount USB drive";
        exec = "${usb-unmount-script}/bin/usb-unmount";
        icon = "drive-removable-media";
        terminal = false;
        type = "Application";
        categories = [ "Utility" ];
      };

      usb-eject-script = writeFileScriptBin {
        name = "usb-eject";
        inherit replacements;
        src = ./usb-menu/usb-eject.bash;
      };
      usb-eject-desktop = makeDesktopItem {
        name = "usb-eject";
        desktopName = "Eject USB device";
        exec = "${usb-eject-script}/bin/usb-eject";
        icon = "media-eject";
        terminal = false;
        type = "Application";
        categories = [ "Utility" ];
      };
    in
    symlinkJoin {
      name = "usb-menu";
      paths = [
        usb-mount-script
        usb-mount-desktop
        usb-unmount-script
        usb-unmount-desktop
        usb-eject-script
        usb-eject-desktop
      ];
    }
  )
  {
    inherit (pkgs)
      bash
      fuzzel
      jq
      libnotify
      udisks2
      util-linux
      ;
  }
