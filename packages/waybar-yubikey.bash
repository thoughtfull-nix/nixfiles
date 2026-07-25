#!@bash@
set -euo pipefail

socket="${XDG_RUNTIME_DIR:-/run/user/$UID}/yubikey-touch-detector.socket"

while true; do
  touch_reasons=()

  if [ ! -e "$socket" ]; then
    printf '{"text": "Waiting for YubiKey socket"}\n'
    while [ ! -e "$socket" ]; do sleep 1; done
  fi
  printf '{"text": ""}\n'

  while read -r -n5 cmd; do
    reason="${cmd:0:3}"

    # HMAC detection is broken with multiple YubiKeys plugged in: it infers touch-waiting
    # from hidraw device disappear/reappear counts, so unplugging any key while another
    # remains gets misread as "still waiting" and never clears. Ignore it entirely.
    # See: https://github.com/max-baz/yubikey-touch-detector/issues/62
    if [ "$reason" = "MAC" ]; then
      continue
    fi

    if [ "${cmd:4:1}" = "1" ]; then
      touch_reasons+=("$reason")
    else
      for i in "${!touch_reasons[@]}"; do
        if [ "${touch_reasons[i]}" = "$reason" ]; then
          unset 'touch_reasons[i]'
          break
        fi
      done
    fi

    if [ "${#touch_reasons[@]}" -eq 0 ]; then
      printf '{"text": ""}\n'
    else
      tooltip="YubiKey is waiting for a touch, reasons: ${touch_reasons[*]}"
      printf '{"text": "", "tooltip": "%s"}\n' "$tooltip"
    fi
  done < <(@nc@ -U "$socket")

  sleep 1
done
