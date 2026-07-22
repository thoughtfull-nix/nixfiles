{ nixpkgs, ... }:
let
  stubs = import ./stubs.nix;
in
nixpkgs.testers.nixosTest {
  name = "minecraft-server";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    enabled =
      {
        config,
        pkgs,
        ...
      }:
      {
        imports = [
          ../nixosModules/minecraft-server.nix
          stubs.impermanence
        ];
        services.minecraft-server.enable = true;

        # Swap the real PaperMC jar for a harmless fake so the test doesn't
        # need internet access to let Paperclip download the vanilla server
        # jar it wraps.
        services.minecraft-server.package = pkgs.writeShellScriptBin "minecraft-server" ''
          echo "fake minecraft server started"
          exec cat
        '';

        assertions = [
          {
            assertion = config.services.minecraft-server.eula;
            message = "eula should default to true";
          }
          {
            assertion = config.services.minecraft-server.declarative;
            message = "declarative should default to true so serverProperties take effect";
          }
          {
            assertion = config.services.minecraft-server.openFirewall;
            message = "openFirewall should default to true";
          }
          {
            assertion = builtins.elem 25565 config.networking.firewall.allowedTCPPorts;
            message = "the default server port should be opened in the firewall";
          }
          {
            assertion = builtins.any (
              d: (d.directory or null) == config.services.minecraft-server.dataDir
            ) config.thoughtfull.impermanence.directories;
            message = "expected minecraft-server dataDir persistence directory";
          }
        ];
      };

    disabled =
      { config, ... }:
      {
        imports = [
          ../nixosModules/minecraft-server.nix
          stubs.impermanence
        ];

        assertions = [
          {
            assertion = !config.services.minecraft-server.enable;
            message = "minecraft-server should stay disabled by default";
          }
          {
            assertion = config.thoughtfull.impermanence.directories == [ ];
            message = "no persistence directory should be added when disabled";
          }
        ];
      };
  };

  testScript = ''
    start_all()
    enabled.wait_for_unit("multi-user.target")
    disabled.wait_for_unit("multi-user.target")

    with subtest("enabled: minecraft-server.service reaches active"):
        enabled.wait_for_unit("minecraft-server.service")
        enabled.succeed("systemctl is-active --quiet minecraft-server.service")

    with subtest("enabled: eula is accepted on disk"):
        eula = enabled.succeed("cat /var/lib/minecraft/eula.txt")
        print(f"eula.txt:\n{eula}")
        assert "eula=true" in eula

    with subtest("enabled: default server properties are rendered declaratively"):
        properties = enabled.succeed("cat /var/lib/minecraft/server.properties")
        print(f"server.properties:\n{properties}")
        assert "difficulty=2" in properties
        assert "gamemode=0" in properties
        assert "max-players=5" in properties
        assert "server-port=25565" in properties

    with subtest("disabled: minecraft-server.service is not present"):
        disabled.fail("systemctl status minecraft-server.service")
  '';
}
