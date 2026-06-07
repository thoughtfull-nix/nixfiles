{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.thoughtfull) dev;
  inherit (lib) mkDefault mkEnableOption mkIf;
  inherit (pkgs) devenv;
in
{
  config = mkIf dev.enable {
    environment.systemPackages = [ devenv ];
    programs = {
      java.package = mkDefault pkgs.javaPackages.compiler.temurin-bin.jdk-25;
    };
    thoughtfull = {
      claude.enable = mkDefault true;
      clojure.enable = mkDefault true;
      rust.enable = mkDefault true;
    };
  };
  options.thoughtfull.dev.enable = mkEnableOption "development configuration";
}
