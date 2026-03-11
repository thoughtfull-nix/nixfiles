{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf mkPackageOption;
  cfg = config.thoughtfull.clojure;
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.babashka.package
      cfg.clj-kondo.package
      cfg.cljfmt.package
      (cfg.clojure.package.override {
        jdk = cfg.jdk.package;
      })
    ];
    services.emacs.thoughtfull = {
      extraConfig = "(use-package thoughtfull-clojure)";
      extraPackages = epkgs: [ epkgs.thoughtfull-clojure ];
    };
  };
  options.thoughtfull.clojure = {
    babashka.package = mkPackageOption pkgs "babashka" {
      default = "babashka";
    };
    clj-kondo.package = mkPackageOption pkgs "clj-kondo" {
      default = "clj-kondo";
    };
    cljfmt.package = mkPackageOption pkgs "cljfmt" {
      default = "cljfmt";
    };
    clojure.package = mkPackageOption pkgs "clojure" {
      default = "clojure";
    };
    enable = mkEnableOption "clojure";
    jdk.package = (mkPackageOption pkgs "jdk" { }) // {
      default = config.programs.java.package;
    };
  };
}
