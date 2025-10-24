{
  lib,
  nixosConfigurations,
  pkgs,
  ...
}:
with pkgs;
rec {
  bashlib = pkgs.writeTextFile {
    name = "bashlib.bash";
    text = builtins.readFile ./bashlib.bash;
  };
  provision = lib.writeArgcScript "provision" ./provision.bash {
    age = "${age}/bin/age";
    bash = "${bash}/bin/bash";
    ssh = "${openssh}/bin/ssh";
    ssh-keygen = "${openssh}/bin/ssh-keygen";
    bashlib = "${bashlib}";
  };
  run-vm = lib.writeArgcScript "run-vm" ./run-vm.bash {
    bash = "${bash}/bin/bash";
    iso = with nixosConfigurations.nixos.config; "${system.build.image}/iso/${image.baseName}.iso";
    ovmf-firmware = pkgs.OVMF.firmware;
    ovmf-variables = pkgs.OVMF.variables;
    qemu = "${qemu}/bin/qemu-system-x86_64";
    qemu-img = "${qemu}/bin/qemu-img";
  };
}
