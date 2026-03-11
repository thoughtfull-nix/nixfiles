{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf mkPackageOption;
  cfg = config.thoughtfull.javascript;
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.nodejs-package ];
    services.emacs.thoughtfull = {
      extraConfig = "(require 'thoughtfull-javascript)";
      extraPackages =
        epkgs: with epkgs; [
          thoughtfull-javascript
        ];
    };
  };
  options.thoughtfull.javascript = {
    enable = mkEnableOption "javascript";
    nodejs-package = mkPackageOption pkgs "nodejs" {
      default = "nodejs_20";
    };
  };
}
