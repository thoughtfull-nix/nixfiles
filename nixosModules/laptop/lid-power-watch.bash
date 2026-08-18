#!@bash@
set -euo pipefail

# Re-evaluate the lid suspend countdown whenever AC power changes, so unplugging
# while the lid is already closed starts the countdown (and plugging back in
# cancels it) -- the lid bindswitch alone can't see power changes. udevadm emits
# one line per power_supply uevent.
#
# `arm` is best-effort (`|| true`): a transient failure must not kill this
# long-running watcher, or Restart=on-failure would crash-loop it every second.
@lid-suspend@ arm || true
@udevadm@ monitor --udev --subsystem-match=power_supply | while read -r _; do
  @lid-suspend@ arm || true
done
