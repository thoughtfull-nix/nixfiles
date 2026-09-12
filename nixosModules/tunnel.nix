{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    concatMap
    concatStringsSep
    filterAttrs
    mapAttrs'
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    types
    ;
  cfg = config.thoughtfull.tunnels;
  enabledTunnels = filterAttrs (_: t: t.enable) cfg;
  bindingArgs =
    b:
    let
      flag = if b.reverse then "-R" else "-L";
      spec =
        if b.reverse then
          "${toString b.remote.port}:localhost:${toString b.local.port}"
        else
          "${toString b.local.port}:localhost:${toString b.remote.port}";
    in
    [
      flag
      spec
    ];
  # These are retransmitted verbatim to ssh by autossh. autossh's own
  # monitoring port is disabled (-M 0, set on the ExecStart below) in favour of
  # SSH-level keepalives (ServerAlive*), which is the modern recommended setup:
  # the keepalives detect a silently dropped link and, with
  # ExitOnForwardFailure, ssh exits so autossh redials.
  sessionArgs =
    t:
    concatStringsSep " " (
      [
        "-N"
        "-o"
        "ExitOnForwardFailure=yes"
        "-o"
        "ServerAliveInterval=30"
        "-o"
        "ServerAliveCountMax=3"
        "-o"
        "StrictHostKeyChecking=accept-new"
        "-i"
        t.identity
        "-p"
        (toString t.port)
      ]
      ++ concatMap bindingArgs t.bindings
      ++ [ "root@${t.host}" ]
    );
in
{
  config = mkIf (enabledTunnels != { }) {
    services.autossh.sessions = mapAttrsToList (name: t: {
      inherit name;
      # The systemd session runs as root so it can read the (root-owned) agenix
      # identity file; it authenticates to the bastion as root@<host>.
      user = "root";
      monitoringPort = 0;
      extraArguments = sessionArgs t;
    }) enabledTunnels;
    # autossh execs `ssh` looked up on PATH, but the upstream autossh unit sets
    # no PATH and the binary has no baked-in ssh path, so make openssh available
    # to each generated session unit.
    systemd.services = mapAttrs' (
      name: _: nameValuePair "autossh-${name}" { path = [ config.programs.ssh.package ]; }
    ) enabledTunnels;
    # The session runs as root and records the accepted peer host key in
    # /root/.ssh/known_hosts. Persist it so StrictHostKeyChecking=accept-new
    # pins the key after the first connection, instead of discarding it on a
    # stateless-root reboot and blindly re-trusting the peer on the next connect.
    thoughtfull.impermanence.directories = [
      {
        directory = "/root/.ssh";
        user = "root";
        group = "root";
        mode = "0700";
      }
    ];
    thoughtfull.monitoring.services = mapAttrsToList (name: _: "autossh-${name}") enabledTunnels;
  };
  options.thoughtfull.tunnels = mkOption {
    default = { };
    description = ''
      Persistent outbound SSH tunnels (via autossh). Each attribute becomes one
      `autossh-<name>.service` that dials `<host>` and holds the configured port
      bindings open, re-establishing the connection after a silent drop.
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          enable = mkEnableOption "this SSH tunnel" // {
            default = true;
          };
          host = mkOption {
            type = types.str;
            description = "Hostname of the SSH peer to dial (connected to as root).";
          };
          port = mkOption {
            type = types.port;
            default = 22;
            description = "SSH port on the peer.";
          };
          identity = mkOption {
            type = types.str;
            description = ''
              Path to the SSH private-key identity file to authenticate with,
              typically an agenix secret path (`config.age.secrets.<n>.path`).
            '';
          };
          bindings = mkOption {
            default = [ ];
            description = "Port forwardings to keep open over the tunnel.";
            type = types.listOf (
              types.submodule {
                options = {
                  reverse = mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      When true, the peer listens on `remote.port` and forwards
                      back to `local.port` on this host (ssh -R). When false,
                      this host listens on `local.port` and forwards to
                      `remote.port` on the peer (ssh -L).
                    '';
                  };
                  local.port = mkOption {
                    type = types.port;
                    description = "Port on this (the client) host.";
                  };
                  remote.port = mkOption {
                    type = types.port;
                    description = "Port on the peer host.";
                  };
                };
              }
            );
          };
        };
      }
    );
  };
}
