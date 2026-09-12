# Lightweight nix eval check (not a VM boot) for nixosModules/tunnel.nix.
#
# thoughtfull.tunnels.<name> is a thin wrapper over the upstream
# services.autossh.sessions: it turns a declarative set of port bindings into
# one autossh session that dials out and holds a persistent SSH connection,
# re-establishing it after a silent drop. Everything under test here is a plain
# eval-time mapping from the tunnel options to the generated
# autossh-<name>.service ExecStart and to thoughtfull.monitoring.services --
# no VM boot needed (and a real autossh session would need a reachable SSH peer
# a test VM can't provide anyway).
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  stubs = import ./stubs.nix;

  # Stub thoughtfull.monitoring.services so the tunnel module can register its
  # autossh unit for failure alerting without pulling in the real monitoring
  # module (which needs the thoughtfull overlay for its ntfy script).
  monitoringServicesStub =
    { lib, ... }:
    {
      options.thoughtfull.monitoring.services = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };

  mkEval =
    extraModule:
    (nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        ../nixosModules/tunnel.nix
        monitoringServicesStub
        stubs.impermanence
        extraModule
      ];
    }).config;

  # A realistic tislit -> buna setup: a reverse binding publishing tislit's
  # local GoToSocial port back on buna's loopback, plus a forward binding to
  # exercise the -L branch too.
  eval = mkEval (
    { ... }:
    {
      thoughtfull.tunnels.buna = {
        host = "buna.thoughtfull.systems";
        identity = "/run/agenix/buna-tunnel-key";
        bindings = [
          {
            reverse = true;
            local.port = 8002;
            remote.port = 8002;
          }
          {
            local.port = 19999;
            remote.port = 19999;
          }
        ];
      };
    }
  );

  # A tunnel with enable = false must produce no session at all.
  disabledEval = mkEval (
    { ... }:
    {
      thoughtfull.tunnels.buna = {
        enable = false;
        host = "buna.thoughtfull.systems";
        identity = "/run/agenix/buna-tunnel-key";
        bindings = [
          {
            reverse = true;
            local.port = 8002;
            remote.port = 8002;
          }
        ];
      };
    }
  );

  # A host that declares no tunnels at all must stay inert.
  emptyEval = mkEval ({ ... }: { });

  execStart = eval.systemd.services."autossh-buna".serviceConfig.ExecStart;

  checks = [
    {
      name = "enabled: an autossh-buna session unit is generated";
      ok = eval.systemd.services ? "autossh-buna";
    }
    {
      name = "enabled: the session runs ssh with -N (no remote command)";
      ok = lib.hasInfix " -N " execStart || lib.hasInfix " -N " "${execStart} ";
    }
    {
      name = "enabled: connects as root@<host> on the default port 22";
      ok = lib.hasInfix "root@buna.thoughtfull.systems" execStart && lib.hasInfix "-p 22" execStart;
    }
    {
      name = "enabled: uses the configured identity file";
      ok = lib.hasInfix "-i /run/agenix/buna-tunnel-key" execStart;
    }
    {
      name = "enabled: a reverse binding emits -R remote:localhost:local";
      ok = lib.hasInfix "-R 8002:localhost:8002" execStart;
    }
    {
      name = "enabled: a non-reverse binding emits -L local:localhost:remote";
      ok = lib.hasInfix "-L 19999:localhost:19999" execStart;
    }
    {
      # ExitOnForwardFailure so a session whose forward can't bind exits (and
      # autossh redials) rather than sitting there uselessly connected; the
      # ServerAlive keepalives are what actually detect a silently dropped link.
      name = "enabled: sets ExitOnForwardFailure and ServerAlive keepalives";
      ok =
        lib.hasInfix "ExitOnForwardFailure=yes" execStart
        && lib.hasInfix "ServerAliveInterval=30" execStart
        && lib.hasInfix "ServerAliveCountMax=3" execStart;
    }
    {
      # accept-new: a brand-new bastion's host key is trusted on first contact
      # (TOFU) so the tunnel comes up without a manual known_hosts step, while
      # still refusing a later key change.
      name = "enabled: StrictHostKeyChecking=accept-new";
      ok = lib.hasInfix "StrictHostKeyChecking=accept-new" execStart;
    }
    {
      # autossh execs `ssh` via PATH; the upstream unit sets none, so the
      # module must put openssh on the unit path or the tunnel never connects.
      name = "enabled: openssh is on the session unit's PATH";
      ok = lib.any (p: lib.hasInfix "openssh" "${p}") eval.systemd.services."autossh-buna".path;
    }
    {
      # So accept-new pins the peer key across stateless-root reboots instead of
      # re-trusting it every boot.
      name = "enabled: root's .ssh (known_hosts) is persisted";
      ok = lib.any (d: (d.directory or d) == "/root/.ssh") eval.thoughtfull.impermanence.directories;
    }
    {
      name = "enabled: the autossh unit is registered for failure monitoring";
      ok = lib.elem "autossh-buna" eval.thoughtfull.monitoring.services;
    }
    {
      name = "enabled: autossh is installed";
      ok = lib.any (p: lib.hasInfix "autossh" "${p}") eval.environment.systemPackages;
    }
    {
      name = "disabled: no session unit when enable = false";
      ok = !(disabledEval.systemd.services ? "autossh-buna");
    }
    {
      name = "disabled: nothing registered for monitoring when enable = false";
      ok = disabledEval.thoughtfull.monitoring.services == [ ];
    }
    {
      name = "empty: a host with no tunnels declares no autossh sessions";
      ok = emptyEval.services.autossh.sessions == [ ];
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    tunnel test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}

    autossh-buna ExecStart:
    ${execStart}
  ''
else
  nixpkgs.runCommand "tunnel-test" { } "touch $out"
