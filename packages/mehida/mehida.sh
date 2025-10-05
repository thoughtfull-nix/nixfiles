#!@bash@/bin/bash
if [[ -v 1 ]]; then
  hostname="${1}"
  workingdir="."
else
  hostname="nixos"
  workingdir="$(mktemp -d)"
fi
disk="${workingdir}/${hostname}.qcow2"
efi_vars="${workingdir}/${hostname}-efi-vars.fd"
disk_size=${2:-100G}
port=${3:-8022}
cp @ovmf-variables@ "${efi_vars}"
chmod 0644 "${efi_vars}"
[[ -e ${disk} ]] || @qemu@/bin/qemu-img create -f qcow2 "${disk}" "${disk_size}"
@qemu@/bin/qemu-system-x86_64 \
  -boot cdn \
  -machine accel=kvm:tcg \
  -cpu max \
  -name mehida \
  -m 8192 \
  -smp 4 \
  -net nic,netdev=user.0,model=virtio \
  -netdev user,id=user.0,hostfwd=tcp::"${port}"-:22 \
  -hda "${disk}" \
  -cdrom @mehida-iso@ \
  -device virtio-keyboard \
  -usb \
  -device usb-tablet,bus=usb-bus.0 \
  -drive if=pflash,format=raw,unit=1,readonly=off,file="${efi_vars}" \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=@ovmf-firmware@
