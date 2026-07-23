{ nixpkgs, ... }:
let
  stubs = import ./stubs.nix;
in
nixpkgs.testers.nixosTest {
  name = "vpn";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    enabled =
      { lib, pkgs, ... }:
      {
        imports = [
          ../nixosModules/vpn.nix
          stubs.ageSecrets
        ];
        # Use a fake plaintext file instead of a real .age fixture so the
        # test doesn't depend on the encrypted secret being decryptable.
        thoughtfull.vpn.configFile = pkgs.writeText "fake-wg-config" "fake";

        # Swap the real wg-quick invocation for a harmless no-op, keeping
        # vpn.nix's own unit name/alias/polkit rule wiring untouched, so the
        # authorization test below doesn't need real WireGuard key material.
        systemd.services.wg-quick-wg0.serviceConfig = lib.mkForce {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
          ExecStop = "${pkgs.coreutils}/bin/true";
        };

        users.users.wheeluser = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
        };
      };

    disabled = {
      imports = [
        ../nixosModules/vpn.nix
        stubs.ageSecrets
      ];
      thoughtfull.vpn.configFile = null;
    };
  };

  testScript = ''
    start_all()
    enabled.wait_for_unit("multi-user.target")
    disabled.wait_for_unit("multi-user.target")

    with subtest("vpn enabled: polkit rule authorizes toggling wg-quick-wg0.service for wheel"):
        rules = enabled.succeed("cat /etc/polkit-1/rules.d/10-nixos.rules")
        assert "org.freedesktop.systemd1.manage-units" in rules, (
            "polkit rule should authorize the systemd manage-units action"
        )
        assert "wg-quick-wg0.service" in rules, (
            "polkit rule should be scoped to the wg-quick-wg0 unit"
        )
        assert "vpn.service" in rules, "polkit rule should authorize the vpn.service alias"
        assert "wheel" in rules, "polkit rule should be scoped to the wheel group"

    with subtest("vpn disabled: no polkit rule is rendered"):
        disabled.fail("test -f /etc/polkit-1/rules.d/10-nixos.rules")

    with subtest("vpn enabled: a non-root wheel user can start/stop the VPN via its alias"):
        # Exercises the real mechanism waybar-network-vpn-toggle relies on:
        # a non-root wheel user calling `systemctl {start,stop} vpn.service`
        # (the alias), authorized by the polkit rule above which matches on
        # the canonical unit id (wg-quick-wg0.service). Not just a rule-text
        # grep -- this confirms systemd resolves the alias to the canonical
        # unit before polkit's action.lookup("unit") check runs.
        enabled.succeed("systemctl stop vpn.service || true")

        enabled.succeed("su wheeluser -c 'systemctl start vpn.service'")
        enabled.succeed("systemctl is-active --quiet vpn.service")

        enabled.succeed("su wheeluser -c 'systemctl stop vpn.service'")
        enabled.fail("systemctl is-active --quiet vpn.service")
  '';
}
