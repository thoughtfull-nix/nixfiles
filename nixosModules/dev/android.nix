{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) dev;
  inherit (lib) mkEnableOption mkIf;
in
{
  config = mkIf (dev.enable && dev.android.enable) {
    # systemd handles uaccess for adb devices and /dev/kvm is world-accessible, so no extra groups
    environment = {
      # Prefer the SDK's adb over android-tools' so shells and Studio share one adb server version
      extraInit = ''
        export ANDROID_HOME="$HOME/Android/Sdk"
        export PATH="$ANDROID_HOME/platform-tools:$PATH"
      '';
      systemPackages = with pkgs; [
        android-studio
        android-tools
      ];
    };
    # Libraries Android Studio's wrapper provides to the emulator, so SDK binaries also run
    # outside it
    programs.nix-ld.libraries = with pkgs; [
      alsa-lib
      dbus
      expat
      libbsd
      libdrm
      libGL
      libice
      libpng
      libpulseaudio
      libsm
      libuuid
      libx11
      libxcb
      libxcb-cursor
      libxcb-image
      libxcb-keysyms
      libxcb-render-util
      libxcb-wm
      libxcomposite
      libxcursor
      libxdamage
      libxfixes
      libxkbcommon
      libxkbfile
      libxrandr
      nspr
      nss_latest
      wayland
    ];
    # Back up projects, Studio settings, Gradle config, and adb/signing keys, but not the
    # re-downloadable SDK, Gradle and Studio caches, Studio plugins, emulator images, or module
    # build outputs (matched by depth so source packages named build are kept).
    thoughtfull.impermanence.user.directories = [
      {
        directory = "AndroidStudioProjects";
        backupExclude = [
          "**/.gradle"
          "**/.kotlin"
          "*/*/*/build"
          "*/*/build"
          "*/build"
        ];
      }
      {
        directory = ".android";
        backupExclude = [
          "avd"
          "cache"
        ];
      }
      ".config/Google"
      {
        directory = ".gradle";
        backupExclude = [
          ".tmp"
          "caches"
          "daemon"
          "jdks"
          "native"
          "wrapper"
        ];
      }
      {
        directory = "Android";
        backup = false;
      }
      {
        directory = ".cache/Google";
        backup = false;
      }
      {
        directory = ".local/share/Google";
        backup = false;
      }
    ];
  };
  options.thoughtfull.dev.android.enable = mkEnableOption "Android development configuration";
}
