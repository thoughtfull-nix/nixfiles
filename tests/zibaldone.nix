# Lightweight nix eval check (not a nixosTest/VM boot) for zibaldone.nix: the
# package is installed, its data is persisted and backed up, its rebuildable
# search index cache is persisted but kept out of backups, and Firefox gets the
# web clipper extension and its native messaging host.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  stubs = import ./stubs.nix;

  mkEval =
    extraModule:
    nixosSystem {
      system = nixpkgs.stdenv.hostPlatform.system;
      lib = self.lib;
      modules = [
        { nixpkgs.overlays = [ self.inputs.zibaldone.overlays.default ]; }
        ../nixosModules/zibaldone.nix
        stubs.impermanence
        extraModule
      ];
    };

  enabled = mkEval { thoughtfull.programs.zibaldone.enable = true; };
  disabled = mkEval { };
  hasZibaldone =
    eval: lib.any (p: (p.pname or "") == "zibaldone") eval.config.environment.systemPackages;
  userDir =
    eval: path:
    lib.findFirst (
      d: (d.directory or d) == path
    ) null eval.config.thoughtfull.impermanence.user.directories;
  clipperId = "web-clipper@zibaldone.thoughtfull.systems";
  clipper = eval: eval.config.programs.firefox.policies.ExtensionSettings.${clipperId} or null;
  hasNativeHost =
    eval:
    lib.any (
      p: (p.pname or "") == "zibaldone"
    ) eval.config.programs.firefox.nativeMessagingHosts.packages;
  dataDir = userDir enabled ".local/share/zibaldone";
  cacheDir = userDir enabled ".cache/zibaldone";

  checks = [
    {
      name = "enabled: zibaldone is installed";
      ok = hasZibaldone enabled;
    }
    {
      name = "enabled: zibaldone data is persisted and backed up";
      ok = dataDir != null && (dataDir.backup or true);
    }
    {
      name = "enabled: zibaldone cache is persisted but not backed up";
      ok = cacheDir != null && !(cacheDir.backup or true);
    }
    {
      name = "enabled: web clipper is force-installed from the store";
      ok =
        clipper enabled == {
          installation_mode = "force_installed";
          install_url = "file://${enabled.pkgs.zib-web-clipper-signed}/zib-web-clipper.xpi";
        };
    }
    {
      name = "enabled: zibaldone native messaging host is registered";
      ok = hasNativeHost enabled;
    }
    {
      name = "disabled: zibaldone is not installed";
      ok = !hasZibaldone disabled;
    }
    {
      name = "disabled: web clipper is not installed";
      ok = clipper disabled == null;
    }
    {
      name = "disabled: no native messaging host";
      ok = !hasNativeHost disabled;
    }
    {
      name = "disabled: nothing persisted";
      ok = disabled.config.thoughtfull.impermanence.user.directories == [ ];
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    zibaldone test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "zibaldone-test" { } "touch $out"
