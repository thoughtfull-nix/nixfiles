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
    elem
    mkDefault
    mkIf
    mkOption
    mkOptionDefault
    types
    ;
  inherit (lib.thoughtfull) githubKeys;
  inherit (pkgs) runCommand writeText;
  inherit (pkgs.lib.strings) join;
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
in
{
  config = {
    age.secrets = mkIf (cfg.hashedPasswordFile != null) {
      hashed-user-passphrase.file = cfg.hashedPasswordFile;
    };
    environment = {
      etc.u2f-mappings.text = "${cfg.name}:${join ":" cfg.u2fKeys}";
      etc."ssh/authorized_keys.d/${cfg.name}_sudo".text = join "\n" cfg.sudoKeys;
      systemPackages = [ templates ];
    };
    services.accounts-daemon.enable = mkDefault true;
    thoughtfull.impermanence.user.directories = mkIf graphical.enable [
      "Documents"
      "src"
    ];
    users = {
      mutableUsers = lib.mkDefault false;
      users = {
        root.openssh.authorizedKeys.keys = mkIf wheel user.openssh.authorizedKeys.keys;
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
    sudoKeys = mkOption {
      default = [
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIHzxKqcMxNuT0xz2JmSHjnm9CRGUpg8Ruc4N6/n2aD36AAAAHXNzaDp0ZWNobm9zb3BoaXN0K3N1ZG9AeXBhNzY2 technosophist+sudo@ypa766"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINFiiNn+Gl1hDcOb9NuwrpnKJsNgIcqwBjHxAEH0x0A0AAAAHXNzaDp0ZWNobm9zb3BoaXN0K3N1ZG9AeXBjOTQw technosophist+sudo@ypc940"
      ];
      type = types.listOf types.str;
    };
    u2fKeys = mkOption {
      default = [
        "oT99wIYvvo+F72re33Fct85LkuAHjP5zsc1ctzwsrLKTHc7jdV+GcLRwR/PwcY3H59cyVzY9ZKqDGZDEfr9+NQ==,Re3sR6/+MGJiRdD5L27J4ZEyJ2vJsoedBYLW7jOVD/mdMyhRBFZ9defOFqGBY32AyjpAJiyKyW93EWt7JrXCvw==,es256,+presence+pin"
        "prPeZJrJt9NnUSfzhkV5m/C6NW4drWhZEzWgD6XInGWklUfDdyRynsYgrCy8eY0xYGwetR+hE5rKB5n64W86IQ==,STWxyk82p42aqpQVg9PERPkKBB5s8HxuKA1sEwKU7801LYuHitYJH9plaEr0PY2aQF/aacOiO4mED1Huqb+vYg==,es256,+presence+pin"
      ];
      type = types.listOf types.str;
    };
  };
}
