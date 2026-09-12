{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mapAttrs
    mapAttrsToList
    mkIf
    mkOption
    optionalString
    types
    ;
  cfg = config.thoughtfull.caddy;
in
{
  config = mkIf (cfg.proxies != { }) {
    # An entry with neither backend nor extraConfig emits an empty vhost block,
    # which Caddy rejects at startup with an opaque parse error; catch it here.
    assertions = mapAttrsToList (name: p: {
      assertion = p.backend != null || p.extraConfig != "";
      message = ''thoughtfull.caddy.proxies."${name}" must set a backend and/or extraConfig.'';
    }) cfg.proxies;

    services.caddy = {
      enable = true;
      email = mkIf (cfg.email != null) cfg.email;
      # Caddy's reverse_proxy transparently upgrades WebSocket connections, so
      # nothing extra is needed for e.g. GoToSocial's streaming API. TLS is
      # Caddy's automatic HTTPS (ACME), so no security.acme wiring here.
      virtualHosts = mapAttrs (_vhost: p: {
        extraConfig = optionalString (p.backend != null) "reverse_proxy ${p.backend}\n" + p.extraConfig;
      }) cfg.proxies;
    };
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };

  options.thoughtfull.caddy = {
    email = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Email address for the ACME account Caddy uses to obtain certificates
        via automatic HTTPS. Should be set whenever any proxies are declared.
      '';
    };
    proxies = mkOption {
      default = { };
      description = ''
        Caddy virtual hosts keyed by site address. Declaring any proxy enables
        Caddy and opens ports 80/443. Each entry reverse-proxies to `backend`
        (if set) and/or emits raw Caddyfile directives from `extraConfig` (for
        redirect-only vhosts, extra headers, etc.).
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            backend = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Upstream to reverse-proxy this vhost to, e.g. \"http://localhost:8002\".";
            };
            extraConfig = mkOption {
              type = types.lines;
              default = "";
              description = "Raw Caddyfile directives appended to this vhost's block.";
            };
          };
        }
      );
    };
  };
}
