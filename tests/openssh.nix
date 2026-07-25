# Lightweight nix eval check (not a nixosTest/VM boot) for the sudo PAM
# ordering wired up in nixosModules/openssh.nix: pam_u2f (yubikey touch) tried
# before pam_rssh (ssh-agent forwarding), with rssh scoped to the dedicated
# sudo key file.
#
# A VM boot was considered and rejected: NixOS's PAM module renders the whole
# /etc/pam.d/sudo file into config.security.pam.services.sudo.text at eval
# time -- nothing about a real authentication attempt is under test here, so
# reading that string directly gives byte-for-byte the same content a VM's
# `cat /etc/pam.d/sudo` would, without needing to boot anything.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  defaultModule = import ../nixosModules/default.nix {
    inputs = self.inputs // {
      inherit self;
    };
  };

  eval = nixosSystem {
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
          # name must match the default keysHash so githubKeys hits the Nix store
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
    ];
  };

  pamSudoLines = lib.splitString "\n" eval.config.security.pam.services.sudo.text;
  indexed = lib.imap0 (i: line: { inherit i line; }) pamSudoLines;
  authLines = builtins.filter (
    e: lib.hasInfix "pam_u2f.so" e.line || lib.hasInfix "libpam_rssh.so" e.line
  ) indexed;
  u2fEntries = builtins.filter (e: lib.hasInfix "pam_u2f.so" e.line) indexed;
  rsshEntries = builtins.filter (e: lib.hasInfix "libpam_rssh.so" e.line) indexed;

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
