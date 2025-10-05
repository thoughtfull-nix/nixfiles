{ nixosConfigurations, pkgs, ... }:
let
  cfg = nixosConfigurations.mehida.config;
  mehida-iso = "${cfg.system.build.image}/iso/${cfg.image.baseName}.iso";
  mehida-script = pkgs.replaceVars ./mehida.sh {
    inherit (pkgs) bash qemu;
    inherit mehida-iso;
    ovmf-firmware = pkgs.OVMF.firmware;
    ovmf-variables = pkgs.OVMF.variables;
  };
in
pkgs.runCommandLocal "mehida" { } ''
  mkdir -p $out/bin
  cp "${mehida-iso}" $out/mehida.iso
  cp "${mehida-script}" $out/bin/mehida
  chmod +x $out/bin/mehida
''
# echo "test" >/tmp/secret.key
# nix run github:nix-community/disko/v1.11.0 -- --mode destroy,format,mount --flake github:thoughtfull-nix/nixfiles/gemariah#gemariah
# ssh -A root@localhost -p 8022 -- nixos-generate-config --no-filesystems --show-hardware-config >hardware-configuration.nix
# nixos-install --flake github:thoughtfull-nix/nixfiles/gemariah#gemariah --no-root-password
