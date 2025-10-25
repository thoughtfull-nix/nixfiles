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
    bashlib = "${bashlib}";
    ssh = "${openssh}/bin/ssh";
    ssh-copy-id = "${openssh}/bin/ssh-copy-id";
    ssh-keygen = "${openssh}/bin/ssh-keygen";
  };
  run-vm = lib.writeArgcScript "run-vm" ./run-vm.bash {
    bash = "${bash}/bin/bash";
    bashlib = "${bashlib}";
    iso = with nixosConfigurations.nixos.config; "${system.build.image}/iso/${image.baseName}.iso";
    ovmf-firmware = pkgs.OVMF.firmware;
    ovmf-variables = pkgs.OVMF.variables;
    qemu = "${qemu}/bin/qemu-system-x86_64";
    qemu-img = "${qemu}/bin/qemu-img";
  };
}
