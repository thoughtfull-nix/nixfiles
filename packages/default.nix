{
  lib,
  nixosConfigurations,
  pkgs,
  ...
}:
with pkgs;
rec {
  ttfl-nixos-vm = lib.writeArgcScript "ttfl-nixos-vm" ./ttfl-nixos-vm.bash {
    bash = "${bash}/bin/bash";
    iso = with nixosConfigurations.nixos.config; "${system.build.image}/iso/${image.baseName}.iso";
    ovmf-firmware = pkgs.OVMF.firmware;
    ovmf-variables = pkgs.OVMF.variables;
    qemu = "${qemu}/bin/qemu-system-x86_64";
    qemu-img = "${qemu}/bin/qemu-img";
  };
}
