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
          # Import the sway/waybar module and its direct dependencies
          ../nixosModules/sway/waybar.nix
          # Define minimal thoughtfull.user option for the test
          {
            options.thoughtfull.user.name = lib.mkOption {
              type = lib.types.str;
              default = "testuser";
            };
          }
        ];

        # Pass thoughtfull as a module argument
        _module.args = { inherit thoughtfull; };

        # Configure thoughtfull user (required for the restart service)
        thoughtfull.user.name = "testuser";

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
        # Check that the restart service exists as a system service
        machine.succeed("test -f /etc/systemd/system/restart-yubikey-touch-detector.service")

        # Verify the service has the correct Type
        result = machine.succeed("grep 'Type=oneshot' /etc/systemd/system/restart-yubikey-touch-detector.service")
        print(f"Service type: {result}")

        # Verify the service restarts yubikey-touch-detector
        result = machine.succeed("grep 'ExecStart=.*systemctl.*--user.*restart yubikey-touch-detector.service' /etc/systemd/system/restart-yubikey-touch-detector.service")
        print(f"ExecStart: {result}")

        # Verify the service runs as the correct user
        result = machine.succeed("grep 'User=testuser' /etc/systemd/system/restart-yubikey-touch-detector.service")
        print(f"User: {result}")

    with subtest("restart service has correct dependencies"):
        # Verify After=suspend.target
        result = machine.succeed("grep 'After=.*suspend.target' /etc/systemd/system/restart-yubikey-touch-detector.service")
        print(f"After dependency: {result}")

        # Verify WantedBy=suspend.target
        result = machine.succeed("grep 'WantedBy=.*suspend.target' /etc/systemd/system/restart-yubikey-touch-detector.service")
        print(f"WantedBy dependency: {result}")

    with subtest("restart service is enabled"):
        # Check that the service symlink exists in suspend.target.wants
        machine.succeed("test -L /etc/systemd/system/suspend.target.wants/restart-yubikey-touch-detector.service")
  '';
}
