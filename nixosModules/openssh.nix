{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) ssh;
  inherit (config.thoughtfull) graphical user;
  inherit (lib) mkDefault mkIf mkOverride;
  inherit (pkgs.thoughtfull) ssh-askpass writeFileScriptBin;
  sshAgentAddKeysScript = writeFileScriptBin {
    name = "ssh-agent-add-keys";
    src = ./openssh/ssh-agent-add-keys.bash;
  };
in
{
  environment = {
    systemPackages = mkIf graphical.enable [ ssh-askpass ];
    # The ssh-agent-add-keys unit (below) only reloads keys on ssh-agent
    # start and, for graphical logins, on sway-session.target -- neither of
    # which fires for a plain console re-login while the systemd --user
    # manager and ssh-agent.service persist across logout, which they can
    # even without lingering enabled. Running the loader directly here, once
    # per login shell, covers that case.
    loginShellInit = mkIf ssh.startAgent (
      let
        # SSH_ASKPASS_REQUIRE=never: on graphical hosts, sway.nix's
        # sessionVariables.SSH_ASKPASS_REQUIRE = "prefer" applies PAM-wide,
        # including plain console sessions -- left as-is, a console ssh-add
        # would try to pop the GUI askpass helper with no display to render
        # it on, and PIN-protected keys would silently fail to load. Forcing
        # "never" here makes ssh-add prompt on this session's own terminal
        # instead (touch-only keys don't need a prompt either way).
        # `[ -t 0 ]` skips this for non-interactive login-shell invocations
        # (e.g. `ssh host cmd`) that have no terminal to prompt on.
        loadKeys = ''
          if [ -t 0 ]; then
            SSH_ASKPASS_REQUIRE=never ${sshAgentAddKeysScript}/bin/ssh-agent-add-keys || true
          fi
        '';
      in
      if graphical.enable then
        ''
          # tty1 is where sway autologins (see sway.nix): defer to the
          # ssh-agent-add-keys unit's own sway-session.target trigger there,
          # timed to run once Wayland/DISPLAY are actually available (needed
          # for PIN-protected keys' GUI askpass) instead of blocking the tty1
          # login on a touch/PIN prompt before exec'ing sway.
          if [ "$(tty)" != "/dev/tty1" ]; then
            ${loadKeys}
          fi
        ''
      else
        loadKeys
    );
  };
  programs.ssh = {
    # An absolute path, not just "ssh-askpass": the ssh-agent systemd unit's
    # own askpass wrapper execs this with the unit's minimal generated PATH
    # (no /run/current-system/sw/bin), so a bare command name silently fails
    # to resolve there. That failure is invisible for touch-only FIDO2 keys
    # (their notify-only prompt never needs a real answer) but breaks PIN
    # (verify-required) keys: ssh-agent gets no PIN back and the signature
    # is refused with a misleading "incorrect passphrase" error.
    #
    # /run/current-system/sw/bin/ssh-askpass rather than "${ssh-askpass}/bin/
    # ssh-askpass": the long-lived ssh-agent systemd unit resolves this path
    # fresh on every invocation, so it keeps working across a nixos-rebuild
    # switch without needing a restart. A baked-in store path would go stale
    # (and eventually be garbage-collected) the moment ssh-askpass rebuilds.
    askPassword = mkIf graphical.enable "/run/current-system/sw/bin/ssh-askpass";
    enableAskPassword = mkDefault graphical.enable;
    extraConfig = ''
      VerifyHostKeyDNS yes
      VisualHostKey yes
      # Workaround: Firewalla returns :: (IPv6 unspecified) AAAA records for
      # .lan hosts even with IPv6 disabled, causing SSH to fall back to
      # localhost when the target refuses the connection. Remove this if
      # Firewalla fixes their DNS behavior.
      Match host *.lan
        AddressFamily inet
    '';
    knownHostsFiles = [
      ./openssh/known_hosts_github
    ];
    startAgent = true;
  };
  security.pam = {
    # rssh will authenticate using ssh-agent.
    rssh = {
      enable = mkDefault true;
      # I have for sudo a separate key on my yubikey that requires touch.
      settings.auth_key_file = mkDefault "/etc/ssh/authorized_keys.d/\${ruser}_sudo";
    };
    services.sudo = {
      # I can ssh into a machine with agent forwarding and touch my yubikey locally to authenticate
      # sudo.
      rssh = mkDefault true;
      # Both u2f and rssh are "sufficient", so auth stops at whichever succeeds first: prefer
      # touching the yubikey directly by running u2f before rssh. rssh then only kicks in as a
      # fallback when the yubikey isn't directly plugged in, e.g. over agent-forwarded ssh.
      #
      # mkOverride 999 rather than mkDefault: the upstream default for this option is itself
      # mkDefault (priority 1000), so a same-priority mkDefault here would conflict instead of
      # overriding it. Priority 999 wins over that default while still leaving a plain value (or
      # mkForce) in a host config free to override this in turn, same as rssh.order itself.
      rules.auth.u2f.order = mkOverride 999 (
        config.security.pam.services.sudo.rules.auth.rssh.order - 10
      );
    };
  };
  services.openssh.hostKeys = [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  systemd = {
    # my boostrapping process uses a preconfigured key for hosts, so I don't need automatic keygen
    services.sshd-keygen.enable = mkDefault false;
    user.services.ssh-agent-add-keys = mkIf ssh.startAgent {
      description = "Load ${user.name}'s SSH auth/signing keys into ssh-agent";
      # Two independent triggers to run this: ssh-agent.service (covers boot,
      # and any agent restart) and sway-session.target (covers logging out
      # and back into a graphical session -- sway's nixos.conf explicitly
      # starts/stops that target per session, so it cycles even when
      # ssh-agent.service and the systemd --user manager itself persist
      # across a logout).
      #
      # No RemainAfterExit: a plain oneshot resets to inactive the instant
      # ExecStart exits, so *every* subsequent activation of either trigger
      # -- in any order, first time or repeat -- enqueues a real start job
      # that re-runs this. RemainAfterExit=true was tried first and doesn't
      # work for this: once latched active by whichever trigger fires first,
      # the other trigger's activation is a no-op against an already-active
      # unit, so it only re-runs on a trigger's *second* activation (e.g. a
      # second graphical logout/login), not its first -- observed on hydor as
      # a first sway login after an earlier console login never reloading
      # keys. The only cost of dropping it is an idempotent double-run when
      # both triggers land in the same transaction (e.g. booting straight
      # into a graphical session with no prior console login).
      after = [
        "ssh-agent.service"
        "sway-session.target"
      ];
      wantedBy = [
        "ssh-agent.service"
        "sway-session.target"
      ];
      # bash: the script's `#!/usr/bin/env bash` shebang needs bash resolvable
      # via env's PATH, which systemd --user units don't get for free.
      path = [
        pkgs.bash
        ssh.package
      ];
      environment = {
        # Without this, this non-interactive oneshot unit would talk to no
        # agent at all.
        SSH_AUTH_SOCK = "%t/ssh-agent";
        # No DISPLAY here: the askpass helper (packages/ssh-askpass.bash) execs
        # x11-ssh-askpass directly, which needs a real X11 display to open a
        # window -- a placeholder value can't satisfy that (unlike the
        # ssh-agent unit itself, whose own DISPLAY=fake only has to satisfy
        # OpenSSH's `getenv("DISPLAY") != NULL` gate for its own agent-side
        # confirm prompts, not actually open a display). Leaving DISPLAY unset
        # here means this unit inherits whatever the systemd --user manager's
        # environment already has -- nothing at the ssh-agent.service-triggered
        # boot run, but the real DISPLAY once sway's nixos.conf imports it
        # ahead of starting sway-session.target, same as every other
        # sway-session.target unit (waybar, mako, kanshi) already relies on.
        SSH_ASKPASS = mkIf graphical.enable "/run/current-system/sw/bin/ssh-askpass";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${sshAgentAddKeysScript}/bin/ssh-agent-add-keys";
      };
    };
  };
  thoughtfull.impermanence = {
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
    user.directories = [
      {
        directory = ".ssh";
        mode = "0700";
      }
    ];
  };
}
