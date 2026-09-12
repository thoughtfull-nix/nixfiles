{ inputs, ... }:
{
  modules = [
    "${inputs.nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
    (
      { ... }:
      {
        ec2.efi = true;
        networking.hostName = "buna";
        nixpkgs.hostPlatform = "aarch64-linux";
        system.stateVersion = "25.11";

        # tislit dials a reverse SSH tunnel in as root to publish GoToSocial on
        # this host's loopback; trust only that deploy key's public half.
        users.users.root.openssh.authorizedKeys.keyFiles = [
          ./buna/tislit-tunnel.pub
        ];

        thoughtfull = {
          # Read-only S3 cache creds so system-pull can fetch and switch to new
          # closures (this is how the bastion gets security updates). Encrypted
          # to buna's own EC2 host key -- created during provisioning.
          binaryCache.awsCredentialsFile = ./buna/secrets/nix-cache-credentials.age;

          caddy = {
            email = "technosophist@thoughtfull.systems";
            proxies = {
              # GoToSocial, reached over the reverse tunnel's loopback endpoint.
              "social.thoughtfull.systems".backend = "http://localhost:8002";

              # Apex domain: account-domain is thoughtfull.systems while the
              # instance is served at social.thoughtfull.systems, so federation
              # discovery hitting the apex must be redirected to the social
              # subdomain; everything else goes to www.
              "thoughtfull.systems".extraConfig = ''
                @wellknown path /.well-known/webfinger /.well-known/host-meta /.well-known/nodeinfo
                redir @wellknown https://social.thoughtfull.systems{uri} permanent
                redir https://www.thoughtfull.systems{uri} permanent
              '';
            };
          };

          # Stateless EC2 edge node: no disko/LUKS/impermanence, no
          # restic/syncthing; see nixosModules/ec2.nix.
          ec2.enable = true;
        };
      }
    )
  ];
  system = "aarch64-linux";
}
