# Lightweight nix eval check (not a VM boot) for nixosModules/ec2.nix and the
# boot.nix gate it drives.
#
# thoughtfull.ec2.enable adapts a host for running as a stateless AWS EC2
# instance: the amazon-image profile supplies the root filesystem and
# bootloader, so this repo's physical-host machinery (disko/LUKS/impermanence,
# restic, syncthing, systemd-boot + FIDO2 LUKS unlock) must step aside -- while
# keeping the system-pull auto-update path so the bastion still gets security
# updates. All of that is eval-time option wiring; no VM boot needed.
{ self, nixpkgs, ... }:
let
  inherit (nixpkgs) lib;
  inherit (self.inputs.nixpkgs.lib) nixosSystem;

  defaultModule = import ../nixosModules/default.nix {
    inputs = self.inputs // {
      inherit self;
    };
  };

  mkEval =
    extraModule:
    (nixosSystem {
      system = "aarch64-linux";
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
            thoughtfull.user.name = "technosophist";
            nixpkgs.config = lib.mkForce { };
            # monitoring needs an ntfyTopic when enabled; it isn't under test here.
            thoughtfull.monitoring.enable = lib.mkForce false;
          }
        )
        extraModule
      ];
    }).config;

  # A bastion: EC2 mode on, plus the cache credentials a real bastion supplies
  # (which is what auto-enables binaryCache + system-pull).
  ec2Eval = mkEval (
    { ... }:
    {
      thoughtfull.ec2.enable = true;
      thoughtfull.binaryCache.awsCredentialsFile = builtins.toFile "nix-cache-credentials" "AWS_ACCESS_KEY_ID=test\n";
    }
  );

  # A normal physical host (EC2 mode off) -- the baseline the gate must not
  # affect.
  baselineEval = mkEval ({ ... }: { });

  identity = ec2Eval.age.identityPaths;

  checks = [
    {
      name = "ec2: impermanence (and thus disko/LUKS) is off";
      ok = !ec2Eval.thoughtfull.impermanence.enable;
    }
    {
      name = "ec2: restic backups are off (stateless edge node)";
      ok = !ec2Eval.services.restic.thoughtfull.enable;
    }
    {
      name = "ec2: syncthing is off (stateless edge node)";
      ok = !ec2Eval.services.syncthing.enable;
    }
    {
      name = "ec2: the systemd-boot + FIDO2-LUKS boot block is gated off";
      ok = !ec2Eval.boot.loader.systemd-boot.enable;
    }
    {
      name = "ec2: no phantom 'encrypted' LUKS device is declared";
      ok = !(ec2Eval.boot.initrd.luks.devices ? encrypted);
    }
    {
      name = "ec2: agenix decrypts with the instance host key, not a /persistent path";
      ok =
        lib.elem "/etc/ssh/ssh_host_ed25519_key" identity
        && !(lib.any (p: lib.hasInfix "persistent" "${p}") identity);
    }
    {
      name = "ec2: automatic host-key generation is re-enabled for a fresh instance";
      ok = ec2Eval.systemd.services.sshd-keygen.enable;
    }
    {
      # The small amazon-image ESP (~250MB) with ~85MB kernel+initrd per
      # generation can only fit one generation's switch peak.
      name = "ec2: GRUB keeps one generation for the small ESP";
      ok = ec2Eval.boot.loader.grub.configurationLimit == 1;
    }
    {
      # The whole reason ec2.nix must NOT disable binaryCache/systemPull:
      # supplying the cache creds should auto-enable the daily security-update pull.
      name = "ec2: system-pull stays enabled for security updates";
      ok = ec2Eval.thoughtfull.systemPull.enable;
    }
    {
      name = "baseline: a non-EC2 host still uses systemd-boot";
      ok = baselineEval.boot.loader.systemd-boot.enable;
    }
    {
      name = "baseline: a non-EC2 host still declares the FIDO2 LUKS device";
      ok = baselineEval.boot.initrd.luks.devices ? encrypted;
    }
    {
      name = "baseline: a non-EC2 host still has impermanence on by default";
      ok = baselineEval.thoughtfull.impermanence.enable;
    }
  ];

  failed = builtins.filter (c: !c.ok) checks;
in
if failed != [ ] then
  throw ''
    ec2 test failed:
    ${builtins.concatStringsSep "\n" (map (c: "  - ${c.name}") failed)}
  ''
else
  nixpkgs.runCommand "ec2-test" { } "touch $out"
