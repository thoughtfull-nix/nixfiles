#!@bash@
set -euo pipefail

# Re-evaluate the lid suspend countdown whenever AC power changes, so unplugging
# while the lid is already closed starts the countdown (and plugging back in
# cancels it) -- the lid bindswitch alone can't see power changes. udevadm emits
# one line per power_supply uevent.
@lid-suspend@ arm
@udevadm@ monitor --udev --subsystem-match=power_supply | while read -r _; do
  @lid-suspend@ arm
done
