{
  lib,
  nixosConfigurations,
  pkgs,
  ...
}:
with pkgs;
lib.writeArgcScript "mehida" ./mehida.bash {
  bash = "${bash}/bin/bash";
  iso = with nixosConfigurations.mehida.config; "${system.build.image}/iso/${image.baseName}.iso";
  qemu = "${qemu}/bin/qemu-system-x86_64";
  qemu-img = "${qemu}/bin/qemu-img";
}
