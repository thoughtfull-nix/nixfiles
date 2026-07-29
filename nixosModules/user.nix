{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.age) secrets;
  inherit (config.thoughtfull) graphical;
  inherit (lib)
    concatMapStringsSep
    elem
    genList
    imap0
    listToAttrs
    mkDefault
    mkIf
    mkOption
    mkOptionDefault
    nameValuePair
    optionalAttrs
    types
    ;
  inherit (pkgs) runCommand writeText;
  cfg = config.thoughtfull.user;
  user = config.users.users.${cfg.name};
  wheel = elem "wheel" user.extraGroups;
  icons = runCommand "user-icon" { } ''
    mkdir $out
    cd $out
    ln -s ${cfg.icon} ${cfg.name}
  '';
  templateFile = writeText "user-template" ''
    [User]
    Icon = ${icons}/''${USER}
  '';
  templateDir = "share/accountsservice/user-templates";
  # user icons from https://github.com/NixOS/nixpkgs/issues/163080#issuecomment-1722465663
  templates = runCommand "user-templates" { meta.priority = 0; } ''
    mkdir -p $out/${templateDir}
    cd $out/${templateDir}

    ln -s ${templateFile} administrator
    ln -s ${templateFile} standard
  '';
  # Each u2fKeyFiles entry is age-encrypted separately (so a single key can be
  # added/rotated/removed without re-encrypting the others) and named by
  # position; the activation script below re-joins them with the (possibly
  # per-host) username at runtime instead of baking it into the ciphertext.
  u2fKeySecrets = listToAttrs (
    imap0 (i: file: nameValuePair "u2f-key-${toString i}" { inherit file; }) cfg.u2fKeyFiles
  );
  u2fKeyPaths = genList (i: secrets."u2f-key-${toString i}".path) (builtins.length cfg.u2fKeyFiles);
  u2fMappingLine = concatMapStringsSep ":" (path: "$(cat ${path})") u2fKeyPaths;
in
{
  config = {
    age.secrets =
      optionalAttrs (cfg.hashedPasswordFile != null) {
        hashed-user-passphrase.file = cfg.hashedPasswordFile;
      }
      // u2fKeySecrets;
    environment = {
      etc."ssh/authorized_keys.d/${cfg.name}_sudo".source = cfg.sudoKeysFile;
      systemPackages = [ templates ];
    };
    # yubikey.nix defaults security.pam.u2f.settings.authfile to this same
    # path; when u2fKeyFiles is empty, this removes any file left behind by a
    # previous generation instead of just skipping the write -- otherwise
    # flipping the option back to [ ] on a `nixos-rebuild switch` would leave
    # the old credentials active until the next full boot (forever on
    # non-impermanence hosts).
    #
    # World-readable on purpose: pam_u2f is consulted by PAM stacks that run
    # as the invoking user, not root (e.g. gtklock), so a root-only file
    # breaks those. The key handle is safe to expose locally -- it's useless
    # without the physical yubikey -- the encryption is only to keep it out
    # of the public git repo, not off the installed machine.
    system.activationScripts.thoughtfullU2fMappings = {
      deps = [ "agenixChown" ];
      text =
        if cfg.u2fKeyFiles != [ ] then
          ''
            printf '%s\n' "${cfg.name}:${u2fMappingLine}" > /etc/u2f-mappings
            chmod 0444 /etc/u2f-mappings
          ''
        else
          ''
            rm -f /etc/u2f-mappings
          '';
    };
    services.accounts-daemon.enable = mkDefault true;
    thoughtfull.impermanence.user.directories = mkIf graphical.enable [
      "Documents"
      "src"
    ];
    users = {
      mutableUsers = lib.mkDefault false;
      users = {
        root = {
          openssh.authorizedKeys.keyFiles = mkIf wheel user.openssh.authorizedKeys.keyFiles;
          password = null;
        };
        ${cfg.name} = {
          extraGroups = cfg.extraGroups;
          group = mkOptionDefault cfg.group;
          hashedPassword = mkDefault cfg.hashedPassword;
          hashedPasswordFile = mkIf (cfg.hashedPasswordFile != null) (
            mkDefault secrets.hashed-user-passphrase.path
          );
          home = mkDefault cfg.home;
          isNormalUser = mkDefault true;
          openssh.authorizedKeys.keyFiles = mkDefault cfg.authorizedKeyFiles;
          password = mkDefault cfg.password;
          uid = mkDefault 1000;
        };
      };
    };
  };
  options.thoughtfull.user = {
    authorizedKeyFiles = mkOption {
      default = [
        ./user/ypa766/id_ed25519_sk_rk_auth_technosophist.pub
        ./user/ypc940/id_ed25519_sk_rk_auth_technosophist.pub
      ];
      description = ''
        Paths to authorized_keys-format public key files (one per file, as
        consumed by openssh.authorizedKeys.keyFiles) allowed to log in as this
        user -- and, since it's in the wheel group, as root. Public data --
        not secret -- so these are plain files, not age-encrypted ones.
      '';
      type = types.listOf types.path;
    };
    extraGroups = mkOption {
      default = [ ];
      type = types.listOf types.str;
    };
    final = mkOption {
      default = config.users.users.${cfg.name};
      internal = true;
      type = types.attrsOf types.anything;
    };
    # Not read anywhere in this repo -- nixosModules/git.nix stopped
    # consuming it when github.com/technosophist.github.com switched to
    # hardcoded/authorizedKeyFiles-based identities. Kept because the
    # private kryptonix flake input's per-host modules (hydor/sedna/tislit)
    # still set thoughtfull.user.github.user, and removing the option
    # breaks nixosConfigurations evaluation for those hosts.
    github = {
      keysHash = mkOption {
        default = "1g4ap2gn2hd352xp4cbi3ids0s0i32m10sfrjsm8zra469z9b50p";
        type = types.str;
      };
      user = mkOption {
        default = cfg.name;
        type = types.str;
      };
    };
    group = mkOption {
      default = "";
      type = types.str;
    };
    hashedPassword = mkOption {
      default = null;
      type = types.nullOr (types.passwdEntry types.str);
    };
    hashedPasswordFile = mkOption {
      default = null;
      type = types.nullOr types.path;
    };
    home = mkOption {
      default = "/home/${cfg.name}";
      description = "This and name exist to break an infinite recursion in impermanence.";
      type = types.str;
    };
    icon = mkOption {
      default = ./user/icon.png;
      type = types.nullOr types.path;
    };
    # name is a convenience and home exist to break an infinite recursion in impermanence.  As far
    # as I can tell, the users.users.<user>.home attribute depends on fileSystems because the home
    # directory could be, e.g., an NFS mount?  And impermanence creates a dependency between
    # fileSystems and users.users.<user>.home.  It has its own home configuration for each user and
    # an assertion if it doesn't match the users.users version, but it doesn't try to set one home
    # from the other.  I can set both from here instead of duplicating values or getting an infinite
    # recursion.
    name = mkOption {
      description = "This and name exist to break an infinite recursion in impermanence.";
      type = types.str;
    };
    password = mkOption {
      default = null;
      type = types.nullOr types.str;
    };
    sudoKeysFile = mkOption {
      default = ./user/sudo_keys;
      description = ''
        Path to a file of authorized_keys-format public keys (one per line)
        allowed to sudo, either directly via pam_rssh (ssh-agent forwarding)
        or as the fallback identity behind the yubikey-touch pam_u2f check.
        Public data -- not secret -- so this is a plain file, not an
        age-encrypted one.
      '';
      type = types.path;
    };
    u2fKeyFiles = mkOption {
      default = [
        ../nixosConfigurations/shared/secrets/u2f-primary-ypa766.age
        ../nixosConfigurations/shared/secrets/u2f-backup-ypc940.age
      ];
      description = ''
        Paths to age-encrypted files, one per pam_u2f credential. Each
        file's decrypted plaintext is a single credential fragment --
        `keyHandle,publicKey,es256,+presence+pin` -- with no username and
        no colons, so the same encrypted file can be shared across hosts
        whose `thoughtfull.user.name` differs.

        An activation script decrypts each one (via agenix), joins them
        with `:`, prefixes the (per-host) username, and writes the result
        (world-readable, matching pam_u2f's usual deployment -- non-root
        PAM stacks like gtklock need to read it too) to /etc/u2f-mappings,
        the path `security.pam.u2f.settings.authfile` already defaults to
        in yubikey.nix. The key handles never land in the Nix store in
        plaintext or in this git repo -- only on the installed machine,
        where they're useless without the physical yubikey anyway.

        Defaults to the two shared technosophist yubikeys committed under
        nixosConfigurations/shared/secrets; set to `[ ]` to disable u2f sudo
        authentication on a host, or override with the host's own encrypted
        key files.
      '';
      type = types.listOf types.path;
    };
  };
}
