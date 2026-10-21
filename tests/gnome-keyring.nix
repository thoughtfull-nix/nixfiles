# Lightweight nix eval check (not a nixosTest/VM boot) for gnome-keyring.nix:
# keyrings are persisted, and with FIDO2 recipients a sway login unlocks the
# login keyring with a password age-encrypted to them.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  impermanenceStub =
    { lib, ... }:
    {
      options.thoughtfull.impermanence.user.directories = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [ ];
      };
    };

  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        { nixpkgs.overlays = [ self.overlays.thoughtfull ]; }
        ../nixosModules/gnome-keyring.nix
        impermanenceStub
        extraModule
      ];
    };

  recipients = [
    "age1fido2-hmac1primarytestrecipient"
    "age1fido2-hmac1backuptestrecipient"
  ];
  enabled = mkEval {
    programs.sway.enable = true;
    services.gnome.gnome-keyring.enable = true;
  };
  withRecipients = mkEval {
    programs.sway.enable = true;
    services.gnome.gnome-keyring = {
      enable = true;
      thoughtfull.fido2Recipients = recipients;
    };
  };
  disabled = mkEval { services.gnome.gnome-keyring.thoughtfull.fido2Recipients = recipients; };

  persistsKeyrings =
    eval:
    lib.any (
      d: (d.directory or null) == ".local/share/keyrings" && (d.mode or null) == "0700"
    ) eval.config.thoughtfull.impermanence.user.directories;
  unlockService = eval: eval.config.systemd.user.services.gnome-keyring-unlock or { enable = false; };
  unlockUnit = eval: eval.config.systemd.user.units."gnome-keyring-unlock.service".text or "";

  checks = [
    {
      name = "enabled: keyrings are persisted privately";
      ok = persistsKeyrings enabled;
    }
    {
      name = "enabled without recipients: no unlock service";
      ok = !(unlockService enabled).enable;
    }
    {
      name = "with recipients: unlock service starts with the sway session";
      ok =
        (unlockService withRecipients).enable
        && lib.elem "sway-session.target" (unlockService withRecipients).wantedBy
        && lib.elem "sway-session.target" (unlockService withRecipients).partOf;
    }
    {
      name = "with recipients: unlock service encrypts to every recipient";
      ok = lib.all (r: lib.hasInfix r (unlockUnit withRecipients)) recipients;
    }
    {
      name = "with recipients: unlock service can decrypt with FIDO2, prompt for the PIN, and reach the running daemon";
      ok =
        let
          path = (unlockService withRecipients).path;
          has = name: lib.any (p: lib.hasPrefix name (p.pname or "")) path;
        in
        has "rage" && has "age-plugin-fido2-hmac" && has "pinentry" && has "socat";
    }
    {
      name = "disabled: no keyrings persisted";
      ok = !persistsKeyrings disabled;
    }
    {
      name = "disabled: no unlock service";
      ok = !(unlockService disabled).enable;
    }
  ];
  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    gnome-keyring test failed:
    ${lib.concatMapStringsSep "\n" (c: "  - ${c.name}") failed}
  ''
else
  nixpkgs.runCommand "gnome-keyring-test" { } "touch $out"
