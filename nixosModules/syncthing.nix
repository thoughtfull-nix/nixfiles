# Not sure if it is worth attempting to generate syncthing cert and key, so the bootstrap process
# would be to enable syncthing and let it generate a cert and key, then encrypt them and store them
# in the private repo.
{ config, lib, ... }:
let
  inherit (builtins) attrNames;
  inherit (config.age.secrets) syncthing-cert syncthing-key syncthing-password;
  inherit (config.services) syncthing;
  inherit (config.services.syncthing.thoughtfull) certFile keyFile passwordFile;
  inherit (config.thoughtfull) user;
  inherit (lib)
    foldlAttrs
    mkDefault
    mkIf
    mkOption
    types
    ;
  folders = config.services.syncthing.settings.folders;
  folderDefaults = {
    copyOwnershipFromParent = mkDefault true;
    enable = mkDefault false;
    versioning = mkDefault {
      params.maxAge = "31536000";
      type = "staggered";
    };
  };
  hasCert = certFile != null;
  hasKey = keyFile != null;
in
{
  config = {
    age.secrets = mkIf syncthing.enable {
      syncthing-cert = mkIf hasCert {
        file = certFile;
        owner = syncthing.user;
      };
      syncthing-key = mkIf hasKey {
        file = keyFile;
        owner = syncthing.user;
      };
      syncthing-password = {
        file = passwordFile;
        owner = syncthing.user;
      };
    };
    networking.firewall.allowedTCPPorts = mkIf syncthing.enable [ 8384 ];
    services.syncthing = {
      cert = mkIf hasCert syncthing-cert.path;
      dataDir = user.final.home;
      group = user.final.group;
      guiAddress = "0.0.0.0:8384";
      guiPasswordFile = mkIf syncthing.enable syncthing-password.path;
      key = mkIf hasKey syncthing-key.path;
      openDefaultPorts = mkDefault true;
      relay.enable = false;
      settings = {
        # device ids & external addresses are defined in kryptonix
        devices = {
          bennu.addresses = [
            "tcp://bennu.lan:22000"
          ];
          gemariah.addresses = [
            "tcp://gemariah.lan:22000"
          ];
          hydor.addresses = [
            "tcp://hydor.lan:22000"
          ];
          mira.addresses = [
            "tcp://mira.lan:22000"
          ];
          naarah.addresses = [
            "tcp://naarah.lan:22000"
          ];
          sedna.addresses = [
            "tcp://sedna.lan:22000"
          ];
          tislit.addresses = [
            "tcp://tislit.lan:22000"
          ];
        };
        # folder ids are defined in kryptonix
        folders = {
          archive = folderDefaults // {
            devices = [
              "gemariah"
              "hydor"
              "naarah"
              "tislit"
            ];
            path = mkDefault "~/archive";
          };
          obsidian = folderDefaults // {
            devices = [
              "gemariah"
              "hydor"
              "mira"
              "naarah"
              "tislit"
            ];
            ignorePatterns = [
              ".obsidian/workspace"
              ".obsidian/workspace-mobile.json"
              ".obsidian/workspace.json"
              "Work"
              "work"
            ];
            path = mkDefault "~/obsidian";
          };
          obsidian-work = folderDefaults // {
            devices = [
              "bennu"
              "gemariah"
              "hydor"
            ];
            ignorePatterns = [
              ".obsidian/workspace"
              ".obsidian/workspace.json"
            ];
            path = mkDefault "~/obsidian-work";
          };
          org = folderDefaults // {
            devices = [
              "gemariah"
              "hydor"
              "mira"
              "naarah"
              "tislit"
            ];
            ignorePatterns = [ "work" ];
            path = mkDefault "~/org";
          };
          org-work = folderDefaults // {
            devices = [
              "bennu"
              "gemariah"
              "hydor"
            ];
            path = mkDefault "~/org-work";
          };
          sync = folderDefaults // {
            devices = attrNames syncthing.settings.devices;
            enable = mkDefault true;
            path = mkDefault "~/sync";
          };
        };
        options = {
          localAnnounceEnabled = mkDefault true;
          relaysEnabled = mkDefault false;
          urAccepted = -1;
        };
        gui = {
          address = "0.0.0.0:8384";
          user = "syncthing";
        };
      };
      user = user.name;
    };
    thoughtfull.impermanence.user.directories = mkIf syncthing.enable (
      foldlAttrs (
        dirs: _name: config:
        if config.enable then dirs ++ [ (builtins.substring 2 (-1) config.path) ] else dirs
      ) [ ".config/syncthing" ] folders
    );
  };
  options.services.syncthing.thoughtfull = {
    certFile = mkOption {
      default = null;
      type = types.nullOr types.path;
    };
    keyFile = mkOption {
      default = null;
      type = types.nullOr types.path;
    };
    passwordFile = mkOption {
      description = "Age-encrypted file whose plaintext content is the Syncthing GUI password. Create with `nixfiles secret <HOST> syncthing-passphrase`.";
      type = types.path;
    };
  };
}
