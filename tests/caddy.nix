# Lightweight nix eval check (not a VM boot) for nixosModules/caddy.nix.
#
# thoughtfull.caddy.proxies is a thin wrapper over services.caddy that leans on
# Caddy's automatic HTTPS (so no security.acme wiring): each entry becomes a
# virtualHost that either reverse-proxies to a backend, carries raw Caddyfile
# directives (e.g. redirect-only vhosts), or both. Under test is the eval-time
# mapping from those options to services.caddy + the 80/443 firewall openings.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  mkEval =
    extraModule:
    (nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        ../nixosModules/caddy.nix
        extraModule
      ];
    }).config;

  # A realistic bastion: a reverse-proxied GoToSocial vhost plus a
  # redirect-only apex vhost handling the federation .well-known discovery
  # split (host social.thoughtfull.systems vs account-domain thoughtfull.systems).
  eval = mkEval (
    { ... }:
    {
      thoughtfull.caddy = {
        email = "technosophist@thoughtfull.systems";
        proxies = {
          "social.thoughtfull.systems".backend = "http://localhost:8002";
          "thoughtfull.systems".extraConfig = ''
            @wellknown path /.well-known/webfinger /.well-known/host-meta /.well-known/nodeinfo
            redir @wellknown https://social.thoughtfull.systems{uri} permanent
            redir https://www.thoughtfull.systems{uri} permanent
          '';
        };
      };
    }
  );

  # No proxies declared -> Caddy stays off and the firewall stays closed.
  emptyEval = mkEval ({ ... }: { });

  # A proxy with neither backend nor extraConfig must be caught by an assertion.
  badEval = mkEval (
    { ... }:
    {
      thoughtfull.caddy.proxies."bad.example.com" = { };
    }
  );

  socialVhost = eval.services.caddy.virtualHosts."social.thoughtfull.systems".extraConfig;
  apexVhost = eval.services.caddy.virtualHosts."thoughtfull.systems".extraConfig;
  ports = eval.networking.firewall.allowedTCPPorts;

  checks = [
    {
      name = "enabled: declaring a proxy turns Caddy on";
      ok = eval.services.caddy.enable;
    }
    {
      name = "enabled: the ACME account email is set for automatic HTTPS";
      ok = eval.services.caddy.email == "technosophist@thoughtfull.systems";
    }
    {
      name = "enabled: a backend proxy vhost reverse-proxies to that backend";
      ok = lib.hasInfix "reverse_proxy http://localhost:8002" socialVhost;
    }
    {
      name = "enabled: a redirect-only vhost carries its directives with no reverse_proxy";
      ok =
        lib.hasInfix "redir @wellknown https://social.thoughtfull.systems{uri}" apexVhost
        && !(lib.hasInfix "reverse_proxy" apexVhost);
    }
    {
      name = "enabled: HTTP (80) and HTTPS (443) are opened in the firewall";
      ok = lib.elem 80 ports && lib.elem 443 ports;
    }
    {
      name = "empty: Caddy stays disabled when no proxies are declared";
      ok = !emptyEval.services.caddy.enable;
    }
    {
      name = "empty: the firewall isn't opened when no proxies are declared";
      ok = !(lib.elem 80 (emptyEval.networking.firewall.allowedTCPPorts or [ ]));
    }
    {
      name = "bad: an empty proxy (no backend, no extraConfig) trips an assertion";
      ok = lib.any (a: !a.assertion) badEval.assertions;
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    caddy test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}

    social vhost:
    ${socialVhost}
    apex vhost:
    ${apexVhost}
  ''
else
  nixpkgs.runCommand "caddy-test" { } "touch $out"
