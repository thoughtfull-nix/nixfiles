{ inputs, ... }:
{
  modules = [
    "${inputs.nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
    (
      { lib, ... }:
      {
        ec2.efi = true;
        networking.hostName = "buna";
        nixpkgs.hostPlatform = "aarch64-linux";
        system.stateVersion = "25.11";
        # restrict,port-forwarding: this key exists only for tislit's reverse
        # tunnel, so deny everything (pty/agent/x11/command) except forwarding --
        # a leaked key then can't get a root shell on the internet-facing bastion.
        users.users.root.openssh.authorizedKeys.keys = [
          "restrict,port-forwarding ${lib.fileContents ./buna/tislit-tunnel.pub}"
        ];
        thoughtfull = {
          binaryCache.awsCredentialsFile = ./buna/secrets/nix-cache-credentials.age;
          caddy = {
            email = "technosophist@thoughtfull.systems";
            proxies = {
              "social2.thoughtfull.systems".backend = "http://localhost:8002";
              # Apex domain: account-domain is thoughtfull.systems while the
              # instance is served at social.thoughtfull.systems, so federation
              # discovery hitting the apex must be redirected to the social
              # subdomain; everything else goes to www.
              "thoughtfull.systems".extraConfig = ''
                @wellknown path /.well-known/webfinger /.well-known/host-meta /.well-known/nodeinfo
                redir @wellknown https://social2.thoughtfull.systems{uri} permanent
                redir https://www.thoughtfull.systems{uri} permanent
              '';
            };
          };
          ec2.enable = true;
          user = {
            name = "technosophist";
            extraGroups = [ "wheel" ];
          };
        };
      }
    )
  ];
  system = "aarch64-linux";
}
