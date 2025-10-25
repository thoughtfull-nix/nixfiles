#!@bash@

### © technosophist
###
### This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy
### of the MPL was not distributed with this file, You can obtain one at
### http://mozilla.org/MPL/2.0/.
###
### This Source Code Form is "Incompatible With Secondary Licenses", as defined by the Mozilla
### Public License, v. 2.0.
###
### @meta version ∞

set -eou pipefail
shopt -s nullglob
IFS=$'\n\t'

# shellcheck disable=SC1091
. @bashlib@

## @describe Run NixOS virtual machine
##
## Run a NixOS virtual machine using my custom ISO, unless another ISO is given.  Port forwarding is
## setup to the VM, and the name given is used with DHCP to set the hostname.  Boots with UEFI
## firmware.
##
## @option --iso=@iso@
## name of the virtual machine
##
## @option --name=nixos
## name of the virtual machine
##
## @option --directory=.
## working directory in which to create the virtual machine disk
##
## @option --size=100M
## virtual machine disk size
##
## @option --port=8022
## local port to forward to virtual machine port 22
main() {
  disk="${argc_directory}/${argc_name}.qcow2"
  efi_vars="${argc_directory}/${argc_name}-efi-vars.fd"
  debug "iso=${argc_iso}"
  debug "name=${argc_name}"
  debug "directory=${argc_directory}"
  debug "disk=${disk}"
  debug "efi_vars=${efi_vars}"
  debug "size=${argc_size}"
  debug "port=${argc_port}"

  cp @ovmf-variables@ "${efi_vars}"
  chmod 0644 "${efi_vars}"
  if [[ -e ${disk} ]]; then
    echo "VM disk already exists."
  else
    echo "Creating VM disk."
    @qemu-img@ create -f qcow2 "${disk}" "${argc_size}"
  fi
  @qemu@ \
    -boot cdn \
    -machine accel=kvm:tcg \
    -cpu max \
    -name "${argc_name}" \
    -m 8192 \
    -smp 4 \
    -net nic,netdev=user.0,model=virtio \
    -netdev user,id=user.0,hostfwd=tcp::"${argc_port}"-:22,hostname="${argc_name}",domainname=thoughtfull.systems \
    -hda "${disk}" \
    -cdrom "${argc_iso}" \
    -device virtio-keyboard \
    -usb \
    -device usb-tablet,bus=usb-bus.0 \
    -drive if=pflash,format=raw,unit=1,readonly=off,file="${efi_vars}" \
    -drive if=pflash,format=raw,unit=0,readonly=on,file=@ovmf-firmware@
}
