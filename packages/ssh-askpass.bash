#!@bash@
set -euo pipefail

# OpenSSH sets SSH_ASKPASS_PROMPT=none for notify_start() calls (touch/security-key
# notifications where the response is discarded and the user has other notifications).
# Every other case -- passphrase/PIN entry, host-key verification's yes/no confirm(),
# and SSH_ASKPASS_PROMPT=confirm permission prompts -- needs a real answer.
if [[ ${SSH_ASKPASS_PROMPT:-} == "none" ]]; then
  exit 0
fi

exec @x11_ssh_askpass@ "$@"
