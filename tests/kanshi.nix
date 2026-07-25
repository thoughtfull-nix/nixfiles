# Lightweight nix eval check (not a nixosTest/VM boot) for kanshi's configFile
# gating: verifying thoughtfull.programs.sway.kanshi.enable defaults off
# configFile, and that the rendered /etc/xdg/kanshi/config file and
# systemd.user.services.kanshi are present only when kanshi ends up enabled.
#
# A VM boot was considered and rejected: every assertion here is a presence
# check on environment.etc/systemd.user.services, both plain attrsets in
# `config` -- nothing about kanshi actually running (or the compositor
# reacting to its output) is under test, so booting sway/kanshi for real would
# only pay for a check that pure evaluation already answers.
{ self, nixpkgs, ... }:
let
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
        ../nixosModules/sway/kanshi.nix
        { programs.sway.enable = true; }
        extraModule
      ];
    };

  # No configFile set: enable should default to false and kanshi should be
  # entirely absent (the hydor/sedna case).
  withoutConfigFile = mkEval { };

  # configFile set: enable should default to true and kanshi should be wired
  # up (the aegle case).
  withConfigFile = mkEval (
    { pkgs, ... }:
    {
      thoughtfull.programs.sway.kanshi.configFile = pkgs.writeText "kanshi-config" ''
        profile undocked {
            output eDP-1 enable
        }
      '';
    }
  );

  checks = [
    {
      name = "configFile unset: enable defaults to false";
      ok = !withoutConfigFile.config.thoughtfull.programs.sway.kanshi.enable;
    }
    {
      name = "configFile unset: kanshi config and service are absent";
      ok =
        !(withoutConfigFile.config.environment.etc ? "xdg/kanshi/config")
        && !(withoutConfigFile.config.systemd.user.services ? kanshi);
    }
    {
      name = "configFile set: enable defaults to true";
      ok = withConfigFile.config.thoughtfull.programs.sway.kanshi.enable;
    }
    {
      name = "configFile set: kanshi config and service are present";
      ok =
        (withConfigFile.config.environment.etc ? "xdg/kanshi/config")
        && (withConfigFile.config.systemd.user.services ? kanshi);
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    kanshi test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "kanshi-test" { } "touch $out"
