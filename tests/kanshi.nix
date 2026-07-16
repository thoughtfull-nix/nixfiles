{ nixpkgs, self, ... }:
nixpkgs.testers.nixosTest {
  name = "kanshi";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    # No configFile set: enable should default to false and kanshi should be
    # entirely absent (the hydor/sedna case).
    withoutConfigFile =
      { ... }:
      {
        imports = [ ../nixosModules/sway/kanshi.nix ];
        nixpkgs.overlays = [ self.overlays.thoughtfull ];
        programs.sway.enable = true;
      };

    # configFile set: enable should default to true and kanshi should be
    # wired up (the aegle case).
    withConfigFile =
      { pkgs, ... }:
      {
        imports = [ ../nixosModules/sway/kanshi.nix ];
        nixpkgs.overlays = [ self.overlays.thoughtfull ];
        programs.sway.enable = true;
        thoughtfull.programs.sway.kanshi.configFile = pkgs.writeText "kanshi-config" ''
          profile undocked {
              output eDP-1 enable
          }
        '';
      };
  };

  testScript = ''
    start_all()
    withoutConfigFile.wait_for_unit("multi-user.target")
    withConfigFile.wait_for_unit("multi-user.target")

    with subtest("configFile unset: kanshi config and service are absent"):
        withoutConfigFile.fail("test -f /etc/xdg/kanshi/config")
        withoutConfigFile.fail("test -f /etc/systemd/user/kanshi.service")

    with subtest("configFile set: kanshi config and service are present"):
        withConfigFile.succeed("test -f /etc/xdg/kanshi/config")
        withConfigFile.succeed("test -f /etc/systemd/user/kanshi.service")
  '';
}
