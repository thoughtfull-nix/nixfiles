#!@bash@
set -euo pipefail

# Reports the default sink's volume/mute state for the Waybar
# custom/audio-speaker widget. Polls on an interval and self-heals if a
# click action's signal poke (see speaker-menu.bash/speaker-toggle.bash) is
# ever missed, the same as waybar-network-wifi.
default_sink=$(@pactl@ get-default-sink 2>/dev/null) || default_sink=""
sinks=$(@pactl@ -f json list sinks 2>/dev/null) || sinks="[]"
# shellcheck disable=SC2016
sink=$(@jq@ --arg name "${default_sink}" '[.[] | select(.name == $name)][0] // empty' <<<"${sinks}")

if [[ -z ${default_sink} || -z ${sink} ]]; then
  printf '{"text": "󰝟", "tooltip": "No speaker output available\\nClick to select output", "class": "disabled"}\n'
  exit 0
fi

IFS=$'\t' read -r mute vol_percent desc < <(
  @jq@ -r '[.mute, ([.volume[].value_percent][0] // "0%"), .description] | @tsv' <<<"${sink}"
)
vol="${vol_percent%\%}"

if [[ ${mute} == "true" ]]; then
  icon="󰝟"
  class="muted"
  action="Right-click to unmute"
else
  if ((vol >= 65)); then
    icon="󰕾"
  elif ((vol >= 35)); then
    icon="󰖀"
  else
    icon="󰕿"
  fi
  class="unmuted"
  action="Right-click to mute"
fi

# shellcheck disable=SC2016
@jq@ -cn --arg icon "${icon}" --arg desc "${desc}" --arg vol "${vol_percent}" \
  --arg action "${action}" --arg class "${class}" \
  '{text: $icon, tooltip: ($desc + ": " + $vol + "\nClick to select output\n" + $action), class: $class}'
