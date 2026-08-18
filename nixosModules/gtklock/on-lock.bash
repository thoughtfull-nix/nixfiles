#!@bash@
set -euo pipefail

# gtklock runs this (its config `lock-command`) the moment the screen actually
# locks. Notify systemd that gtklock-session-lock.service (Type=notify) is ready,
# so lock.target -- and, before a suspend, sleep.target -- are only considered
# "reached" once the screen is truly locked, not merely when gtklock forked.
# Without this, systemd-lock-handler releases its sleep inhibitor on the fork and
# the machine suspends before gtklock paints, flashing the unlocked screen on
# resume. Then clear cached credentials (the original lock-command).
@systemd-notify@ --ready || true
exec @clear-secrets@
