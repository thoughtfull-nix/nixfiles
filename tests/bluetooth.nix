# Lightweight nix eval check (not a nixosTest/VM boot) for the WirePlumber
# bluez config: a test VM has no Bluetooth adapter, so there are no profiles
# to inspect at runtime.
{ self, nixpkgs, ... }:
let
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  eval = nixosSystem {
    system = nixpkgs.stdenv.hostPlatform.system;
    lib = self.lib;
    modules = [
      ../nixosModules/bluetooth.nix
      { hardware.bluetooth.enable = true; }
    ];
  };

  bluezProperties =
    eval.config.services.pipewire.wireplumber.extraConfig."10-bluez"."monitor.bluez.properties";

  checks = [
    {
      # an explicit roles list replaces WirePlumber's defaults, which dropped
      # A2DP and left headsets stuck on low-quality HSP/HFP
      name = "bluez5.roles is not overridden";
      ok = !(bluezProperties ? "bluez5.roles");
    }
    {
      name = "codec settings are kept";
      ok =
        bluezProperties."bluez5.enable-sbc-xq"
        && bluezProperties."bluez5.enable-msbc"
        && bluezProperties."bluez5.enable-hw-volume";
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    bluetooth test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "bluetooth-test" { } "touch $out"
