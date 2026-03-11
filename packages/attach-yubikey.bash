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

## @describe Attach yubikey to running qemu VM
main() {
  echo "device_add usb-host,id=yubikey,vendorid=0x1050,productid=0x0406" |
    @nc@ -N -U /tmp/qemu-monitor.sock
}
