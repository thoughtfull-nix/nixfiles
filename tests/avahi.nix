{ nixpkgs, ... }:
nixpkgs.testers.nixosTest {
  name = "avahi";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    server = {
      imports = [ ../nixosModules/avahi.nix ];
      networking.hostName = "testserver";
    };

    client = {
      imports = [ ../nixosModules/avahi.nix ];
      networking.hostName = "testclient";
    };
  };

  testScript = ''
    start_all()

    # Wait for avahi-daemon to be running on both nodes
    server.wait_for_unit("avahi-daemon.service")
    client.wait_for_unit("avahi-daemon.service")

    # Wait for network to settle and allow mDNS to propagate
    import time
    time.sleep(5)

    # Test default configuration values
    with subtest("default: NSS mDNS integration is enabled"):
        # Verify NSS mDNS integration works by using getent (uses NSS, not avahi directly)
        # This will only succeed if nssmdns4 is properly configured
        result = client.succeed("getent hosts testserver.local", timeout=10)
        print(f"NSS lookup result: {result}")
        assert "testserver" in result.lower(), "NSS should resolve .local hostnames"

    with subtest("default: address publishing is enabled"):
        # Forward lookup should work
        result = client.succeed("avahi-resolve -n testserver.local", timeout=10)
        print(f"Forward lookup result: {result}")

        # Get the IP address from forward lookup
        server_ip = client.succeed("avahi-resolve -n testserver.local | awk '{print $2}'").strip()
        print(f"Server IP: {server_ip}")

        # Reverse lookup should work
        reverse_result = client.succeed(f"avahi-resolve -a {server_ip}", timeout=10)
        print(f"Reverse lookup result: {reverse_result}")
        assert "testserver.local" in reverse_result, "Reverse lookup should return hostname"

    with subtest("default: domain publishing is enabled"):
        # Note: Domain publishing relates to wide-area DNS-SD domain announcements
        # and doesn't have an easily testable functional aspect via avahi-browse -D
        # (which shows "+  n/a  n/a" regardless). Verify the config setting instead.
        config_path = server.succeed("systemctl cat avahi-daemon | grep ExecStart | sed 's/.*-f //;s/ .*//'").strip()
        result = server.succeed(f"grep -E '^publish-domain=' {config_path}")
        print(f"Domain publish config: {result}")
        assert "publish-domain=yes" in result, "publish-domain should be 'yes' by default"

    with subtest("default: basic avahi functionality"):
        # Check that avahi binaries are available
        server.succeed("which avahi-browse")
        client.succeed("which avahi-browse")

        # Test that avahi can browse services
        server.succeed("avahi-browse -a -t", timeout=10)
        client.succeed("avahi-browse -a -t", timeout=10)
  '';
}
