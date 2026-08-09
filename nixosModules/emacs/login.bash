#!@bash@
set -euo pipefail

# Unlike foot/firefox/slack, emacsclient doesn't own the window itself -- the
# long-running daemon does -- so pid matching would keep matching every
# future frame that daemon ever creates, not just this one. Tagging this one
# frame with a name and matching on that title instead is what makes this
# self-expire the way pid=$! does for the others: later `emacsclient -c`
# calls (without this frame name) never match.
#
# No retry here: emacs-client-login.service (../emacs.nix) orders this after
# emacs.service and emacs.service is Type=notify, so systemd itself already
# blocks starting this unit until the daemon signals it's ready to accept
# clients -- there's no readiness gap left for a retry to cover.
@swaymsg@ "for_window [title=^login-emacs$] move to workspace 2"
@emacsclient@ -c -F '((name . "login-emacs"))'
