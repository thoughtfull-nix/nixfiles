{ nixpkgs, self, ... }:
let
  # Create a minimal thoughtfull specialArgs for the test
  thoughtfull = {
    lib = self.lib;
    pkgs = self.packages.x86_64-linux;
    nixosModules = self.nixosModules;
  };
in
nixpkgs.testers.nixosTest {
  name = "waybar";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    machine =
      { config, pkgs, lib, ... }:
      {
        imports = [
          # Import only the sway/waybar module and its direct dependencies
          ../nixosModules/sway/waybar.nix
        ];

        # Pass thoughtfull as a module argument
        _module.args = { inherit thoughtfull; };

        # Enable sway and waybar directly (bypassing the graphical module)
        programs.sway.enable = true;
        programs.waybar.enable = true;
        programs.yubikey-touch-detector.enable = true;

        # Create a test user for user services
        users.users.testuser = {
          isNormalUser = true;
          uid = 1000;
        };
      };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("yubikey-touch-detector service exists"):
        # Check that yubikey-touch-detector service file exists
        machine.succeed("test -f /etc/systemd/user/yubikey-touch-detector.service")

    with subtest("restart service exists with correct configuration"):
        # Check that the restart service exists
        machine.succeed("test -f /etc/systemd/user/restart-yubikey-touch-detector.service")

        # Verify the service has the correct Type
        result = machine.succeed("grep 'Type=oneshot' /etc/systemd/user/restart-yubikey-touch-detector.service")
        print(f"Service type: {result}")

        # Verify the service restarts yubikey-touch-detector
        result = machine.succeed("grep 'ExecStart=.*systemctl.*restart yubikey-touch-detector.service' /etc/systemd/user/restart-yubikey-touch-detector.service")
        print(f"ExecStart: {result}")

    with subtest("restart service has correct dependencies"):
        # Verify After=sleep.target
        result = machine.succeed("grep 'After=.*sleep.target' /etc/systemd/user/restart-yubikey-touch-detector.service")
        print(f"After dependency: {result}")

        # Verify WantedBy=sleep.target
        result = machine.succeed("grep 'WantedBy=.*sleep.target' /etc/systemd/user/restart-yubikey-touch-detector.service")
        print(f"WantedBy dependency: {result}")

    with subtest("restart service is enabled for user"):
        # Check that the service symlink exists in sleep.target.wants
        machine.succeed("test -L /etc/systemd/user/sleep.target.wants/restart-yubikey-touch-detector.service")
  '';
}
