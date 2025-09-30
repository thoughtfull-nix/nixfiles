{ nixosConfigurations, pkgs, ... }:
let
  mehida-iso =
    with nixosConfigurations.mehida.config;
    "${system.build.image}/iso/${image.baseName}.iso";
  mehida-script = pkgs.writeScript "mehida" ''
    #!${pkgs.bash}/bin/bash
    disk=$(mktemp)
    ${pkgs.qemu}/bin/qemu-img create -f qcow2 $disk 100M
    ${pkgs.qemu}/bin/qemu-system-x86_64 \
      -boot d \
      -machine accel=kvm:tcg \
      -cpu max \
      -name mehida \
      -m 2048 \
      -smp 1 \
      -net nic,netdev=user.0,model=virtio \
      -netdev user,id=user.0,hostfwd=tcp::8022-:22 \
      -hda $disk \
      -cdrom ${mehida-iso} \
      -device virtio-keyboard \
      -usb \
      -device usb-tablet,bus=usb-bus.0
  '';
in
pkgs.runCommandLocal "mehida" { } ''
  mkdir -p $out/bin
  ln -s "${mehida-iso}" $out/mehida.iso
  ln -s "${mehida-script}" $out/bin/mehida
''
