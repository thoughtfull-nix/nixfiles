{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkDefault mkEnableOption mkIf;
  cfg = config.thoughtfull.codexDesktop;
in
{
  config = mkIf cfg.enable {
    nix.settings = {
      extra-substituters = [ "https://codex-desktop-linux.cachix.org" ];
      extra-trusted-public-keys = [
        "codex-desktop-linux.cachix.org-1:nX/xy6AdK9hQE24A8ALGjkCKj2ObFmcnemiL5Cid4nk="
      ];
    };
    programs = {
      codexDesktopLinux.enable = mkDefault true;
      # Codex Desktop downloads generic Linux runtimes
      nix-ld.enable = mkDefault true;
    };
    thoughtfull.impermanence.user.directories = [
      # re-downloadable runtimes; backups already skip ~/.cache
      ".cache/codex-runtimes"
      {
        directory = ".codex";
        backupExclude = [
          ".tmp"
          "cache"
          "plugins/cache"
          "tmp"
        ];
      }
      {
        directory = ".config/Codex";
        backupExclude = [
          "**/DawnGraphiteCache"
          "**/DawnWebGPUCache"
          "**/GPUCache"
          "GPUPersistentCache"
          "OnDeviceHeadSuggestModel"
          "WasmTtsEngine"
          "WidevineCdm"
          "component_crx_cache"
        ];
      }
      ".config/codex-desktop"
      ".local/state/codex-desktop"
    ];
  };
  options.thoughtfull.codexDesktop.enable = mkEnableOption "Codex Desktop";
}
