#!@bash@
set -eou pipefail

# @meta version ∞
# @option --size=100M virtual machine disk size
# @option --port=8022 local port to forward to virtual machine port 22
main() {
  echo "size=${argc_size}"
  echo "port=${argc_port}"

  disk=$(mktemp)
  @qemu-img@ create -f qcow2 "${disk}" "${argc_size}"
  @qemu@ \
    -boot d \
    -machine accel=kvm:tcg \
    -cpu max \
    -name mehida \
    -m 2048 \
    -smp 1 \
    -net nic,netdev=user.0,model=virtio \
    -netdev user,id=user.0,hostfwd=tcp::"${argc_port}"-:22 \
    -hda "${disk}" \
    -cdrom @iso@ \
    -device virtio-keyboard \
    -usb \
    -device usb-tablet,bus=usb-bus.0
}
