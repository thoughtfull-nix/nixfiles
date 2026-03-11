{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  inherit (pkgs)
    cargo
    clippy
    gcc
    rust-analyzer
    rustc
    rustfmt
    rusty-man
    ;
  cfg = config.thoughtfull.rust;
in
{
  config = mkIf cfg.enable {
    environment = {
      sessionVariables = {
        PATH = "$HOME/.cargo/bin";
      };
      systemPackages = [
        cargo
        clippy
        gcc
        rust-analyzer
        rustc
        rustfmt
        rusty-man
      ];
    };
    services.emacs.thoughtfull = {
      extraConfig = "(require 'thoughtfull-rust)";
      extraPackages = epkgs: [ epkgs.thoughtfull-rust ];
    };
  };
  options.thoughtfull.rust.enable = mkEnableOption "rust";
}
