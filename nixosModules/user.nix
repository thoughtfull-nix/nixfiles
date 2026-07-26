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
  inherit (lib.thoughtfull) githubKeys;
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
    # path; when u2fKeyFiles is empty, nothing writes it and pam_u2f simply
    # fails that auth line (sudo falls through to the rssh/ssh-agent rule).
    system.activationScripts.thoughtfullU2fMappings = mkIf (cfg.u2fKeyFiles != [ ]) {
      deps = [ "agenixChown" ];
      text = ''
        umask 077
        printf '%s\n' "${cfg.name}:${u2fMappingLine}" > /etc/u2f-mappings
        chmod 0400 /etc/u2f-mappings
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
          openssh.authorizedKeys.keys = mkIf wheel user.openssh.authorizedKeys.keys;
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
          openssh.authorizedKeys.keys = githubKeys {
            sha256 = cfg.github.keysHash;
            username = cfg.github.user;
          };
          password = mkDefault cfg.password;
          uid = mkDefault 1000;
        };
      };
    };
  };
  options.thoughtfull.user = {
    extraGroups = mkOption {
      default = [ ];
      type = types.listOf types.str;
    };
    final = mkOption {
      default = config.users.users.${cfg.name};
      internal = true;
      type = types.attrsOf types.anything;
    };
    github = {
      keysHash = mkOption {
        default = "1dzq0125fmng19v088xv7pqq9c42wli75m44cglvxr2xayyz46mr";
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
        to /etc/u2f-mappings mode 0400 -- the path
        `security.pam.u2f.settings.authfile` already defaults to in
        yubikey.nix. The key handles never land in the Nix store in
        plaintext.

        Defaults to the two shared technosophist yubikeys committed under
        nixosConfigurations/shared/secrets; set to `[ ]` to disable u2f sudo
        authentication on a host, or override with the host's own encrypted
        key files.
      '';
      type = types.listOf types.path;
    };
  };
}
