{ self, nixpkgs, ... }:
nixpkgs.testers.nixosTest {
  name = "avahi";

  skipTypeCheck = true;
  skipLint = true;

  nodes = {
    server = {
      imports = [ ../nixosModules/avahi.nix ];

      # The module should enable avahi by default, so we don't set it explicitly
      # This tests that the module's mkDefault true works correctly

      # Add a test service to publish
      services.avahi.publish = {
        userServices = true;
      };

      # Configure hostname for testing
      networking.hostName = "testserver";
      # Firewall should be opened by the module
    };

    client = {
      imports = [ ../nixosModules/avahi.nix ];

      # The module should enable avahi by default, so we don't set it explicitly
      # This tests that the module's mkDefault true works correctly
      networking.hostName = "testclient";
      # Firewall should be opened by the module
    };
  };

  testScript = ''
    server = globals()["testserver"]
    client = globals()["testclient"]

    start_all()

    # Wait for avahi-daemon to be running on both nodes
    server.wait_for_unit("avahi-daemon.service")
    client.wait_for_unit("avahi-daemon.service")

    # Verify avahi-daemon is running
    server.succeed("systemctl is-active avahi-daemon.service")
    client.succeed("systemctl is-active avahi-daemon.service")

    # Check that avahi binaries are available
    server.succeed("which avahi-browse")
    client.succeed("which avahi-browse")

    # Verify NSS mDNS integration is enabled
    server.succeed("grep -q mdns4_minimal /etc/nsswitch.conf")
    client.succeed("grep -q mdns4_minimal /etc/nsswitch.conf")

    # Wait for network to settle and allow mDNS to propagate
    server.sleep(5)
    client.sleep(5)

    # Test mDNS hostname resolution from client to server
    # The server should be resolvable as testserver.local
    with subtest("mDNS hostname resolution"):
        client.succeed("getent hosts testserver.local", timeout=30)

    # Test that avahi can browse services
    with subtest("service browsing"):
        server.succeed("avahi-browse -a -t", timeout=10)
        client.succeed("avahi-browse -a -t", timeout=10)

    # Test that avahi-resolve works
    with subtest("avahi-resolve"):
        server.succeed("avahi-resolve --name testserver.local", timeout=10)

    # Test that address records are being published
    with subtest("address publishing"):
        # Resolve the hostname and capture the IP address
        server_ip = client.succeed("avahi-resolve --name testserver.local | awk '{print $2}'").strip()
        print(f"Server IP from mDNS: {server_ip}")

        # Verify reverse address lookup works (tests that addresses are published)
        reverse_result = client.succeed(f"avahi-resolve-address {server_ip}", timeout=10)
        assert "testserver.local" in reverse_result, "Reverse address lookup should return hostname"

        # Verify the client can also resolve its own address
        client_ip = client.succeed("avahi-resolve --name testclient.local | awk '{print $2}'").strip()
        print(f"Client IP from mDNS: {client_ip}")

    # Test domain publishing by checking browse output
    with subtest("domain publishing"):
        # Browse all services with full details to see what's published
        browse_output = client.succeed("avahi-browse -a -t -r -p", timeout=15)
        # With domain publishing enabled, we should see .local domain announcements
        # The -p flag gives parseable output
        assert ".local" in browse_output, "Domain publishing should announce .local domain"

    # Test that we can discover the server from the client
    with subtest("cross-node discovery"):
        # Verify cross-node name resolution works via mDNS
        # This is the key integration test for avahi functionality
        client.wait_until_succeeds("ping -c 1 testserver.local", timeout=30)
  '';
}
