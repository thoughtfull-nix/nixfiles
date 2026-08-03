# Lightweight nix eval check (not a nixosTest/VM boot) for two things wired up
# in nixosModules/openssh.nix:
#
# - the sudo PAM ordering: pam_u2f (yubikey touch) tried before pam_rssh
#   (ssh-agent forwarding), with rssh scoped to the dedicated sudo key file.
# - the ssh-agent-add-keys systemd --user unit that loads the configured
#   user's auth/signing keys into ssh-agent whenever it starts.
#
# A VM boot was considered and rejected: NixOS's PAM module renders the whole
# /etc/pam.d/sudo file into config.security.pam.services.sudo.text at eval
# time -- nothing about a real authentication attempt is under test here, so
# reading that string directly gives byte-for-byte the same content a VM's
# `cat /etc/pam.d/sudo` would, without needing to boot anything. Likewise, the
# unit's After/WantedBy/ExecStart are plain eval-time config values -- no need
# to boot a VM (and actually loading keys needs a real ssh-agent socket and a
# FIDO2 token anyway, which a VM test can't provide).
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  defaultModule = import ../nixosModules/default.nix {
    inputs = self.inputs // {
      inherit self;
    };
  };

  # Shared eval scaffolding, parameterized by an extra module so each variant
  # below only has to state what it overrides relative to the default host.
  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      specialArgs = {
        inputs = self.inputs // {
          inherit self;
        };
      };
      modules = [
        defaultModule
        (
          { lib, ... }:
          {
            # thoughtfull.user.name has no default and must be set for eval to
            # succeed; this test's checks don't depend on its particular value
            thoughtfull.user.name = "technosophist";
            # clear module-set nixpkgs.config to avoid the "external pkgs instance" assertion
            nixpkgs.config = lib.mkForce { };
            # openssh.nix disables automatic keygen; re-enable to mirror a real host
            systemd.services.sshd-keygen.enable = lib.mkForce true;
            # Disable services that need secrets or required options not suitable for eval
            services.syncthing.enable = lib.mkForce false;
            services.restic.thoughtfull.enable = lib.mkForce false;
            thoughtfull = {
              impermanence.enable = lib.mkForce false;
              monitoring.enable = lib.mkForce false;
            };
          }
        )
        extraModule
      ];
    };

  eval = mkEval ({ ... }: { });

  # graphical.enable pulls in the askpass wiring on the key-loader unit.
  graphicalEval = mkEval (
    { lib, ... }:
    {
      thoughtfull.graphical.enable = lib.mkForce true;
    }
  );

  # startAgent = false must remove the key-loader unit entirely -- it's
  # wanted/bound to a ssh-agent.service that no longer exists in this case.
  noAgentEval = mkEval (
    { lib, ... }:
    {
      programs.ssh.startAgent = lib.mkForce false;
    }
  );

  pamSudoLines = lib.splitString "\n" eval.config.security.pam.services.sudo.text;
  indexed = lib.imap0 (i: line: { inherit i line; }) pamSudoLines;
  authLines = builtins.filter (
    e: lib.hasInfix "pam_u2f.so" e.line || lib.hasInfix "libpam_rssh.so" e.line
  ) indexed;
  u2fEntries = builtins.filter (e: lib.hasInfix "pam_u2f.so" e.line) indexed;
  rsshEntries = builtins.filter (e: lib.hasInfix "libpam_rssh.so" e.line) indexed;

  keyLoader = eval.config.systemd.user.services.ssh-agent-add-keys;

  checks = [
    {
      name = "default: sudo has exactly one pam_u2f and one pam_rssh auth line";
      ok = builtins.length authLines == 2;
    }
    {
      name = "default: sudo tries the yubikey (u2f) before ssh-agent (rssh)";
      ok =
        u2fEntries != [ ]
        && rsshEntries != [ ]
        && (builtins.head u2fEntries).i < (builtins.head rsshEntries).i;
    }
    {
      name = "default: rssh authenticates sudo against the dedicated sudo key file";
      ok =
        rsshEntries != [ ]
        && lib.hasInfix "auth_key_file=/etc/ssh/authorized_keys.d/\${ruser}_sudo" (builtins.head rsshEntries)
        .line;
    }
    {
      # Static wiring only -- this doesn't (and can't, at eval time) verify
      # that logging out and back in actually re-runs the unit; that rests on
      # runtime systemd transaction semantics (sway's nixos.conf starting and
      # stopping sway-session.target once per session) described in
      # nixosModules/openssh.nix.
      name = "default: ssh-agent-add-keys starts alongside and after ssh-agent and each sway session";
      ok =
        lib.elem "ssh-agent.service" keyLoader.after
        && lib.elem "sway-session.target" keyLoader.after
        && lib.elem "ssh-agent.service" keyLoader.wantedBy
        && lib.elem "sway-session.target" keyLoader.wantedBy;
    }
    {
      name = "default: ssh-agent-add-keys talks to the same socket ssh-agent listens on";
      ok = keyLoader.environment.SSH_AUTH_SOCK == "%t/ssh-agent";
    }
    {
      # No RemainAfterExit: a plain oneshot resets to inactive the instant
      # ExecStart exits, so every subsequent activation of either trigger --
      # in any order, first time or repeat -- actually re-runs it, rather
      # than being a no-op against an already-active unit. See
      # nixosModules/openssh.nix.
      name = "default: ssh-agent-add-keys is a plain oneshot with no bindsTo/partOf";
      ok =
        keyLoader.serviceConfig.Type == "oneshot"
        && !(keyLoader.serviceConfig ? RemainAfterExit)
        && keyLoader.bindsTo == [ ]
        && keyLoader.partOf == [ ];
    }
    {
      name = "default: ssh-agent-add-keys runs the ssh-agent-add-keys script";
      ok = lib.hasInfix "/bin/ssh-agent-add-keys" keyLoader.serviceConfig.ExecStart;
    }
    {
      # No DISPLAY assertion: it's deliberately left unset here so the unit
      # inherits whatever the systemd --user manager's environment already
      # has (a real DISPLAY once sway imports it, nothing at boot) -- a
      # placeholder value wouldn't let the askpass helper actually open a
      # window. See nixosModules/openssh.nix.
      name = "graphical: ssh-agent-add-keys gets SSH_ASKPASS for PIN-protected keys";
      ok =
        let
          env = graphicalEval.config.systemd.user.services.ssh-agent-add-keys.environment;
        in
        !(env ? DISPLAY) && env.SSH_ASKPASS == "/run/current-system/sw/bin/ssh-askpass";
    }
    {
      name = "no agent: ssh-agent-add-keys does not exist when startAgent is disabled";
      ok = !(noAgentEval.config.systemd.user.services ? ssh-agent-add-keys);
    }
    {
      # Covers the console-login gap the systemd unit alone can't: neither of
      # its triggers (ssh-agent.service, sway-session.target) fires for a
      # plain console re-login while the systemd --user manager persists
      # across logout.
      name = "default: loginShellInit loads keys on the terminal, not via GUI askpass";
      ok =
        lib.hasInfix "SSH_ASKPASS_REQUIRE=never" eval.config.environment.loginShellInit
        && lib.hasInfix "/bin/ssh-agent-add-keys" eval.config.environment.loginShellInit
        && !(lib.hasInfix "/dev/tty1" eval.config.environment.loginShellInit);
    }
    {
      # tty1 is where sway autologins -- that case is deferred to the
      # ssh-agent-add-keys unit's sway-session.target trigger instead (see
      # nixosModules/openssh.nix), so it shouldn't also run here.
      name = "graphical: loginShellInit skips the console load path on tty1";
      ok =
        lib.hasInfix "/dev/tty1" graphicalEval.config.environment.loginShellInit
        && lib.hasInfix "SSH_ASKPASS_REQUIRE=never" graphicalEval.config.environment.loginShellInit;
    }
    {
      name = "no agent: loginShellInit doesn't try to load keys when startAgent is disabled";
      ok = !(lib.hasInfix "ssh-agent-add-keys" noAgentEval.config.environment.loginShellInit);
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    openssh test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}

    /etc/pam.d/sudo:
    ${eval.config.security.pam.services.sudo.text}
  ''
else
  nixpkgs.runCommand "openssh-test" { } "touch $out"
