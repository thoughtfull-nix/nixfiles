#!@bash@
set -euo pipefail

# Reports the default source's volume/mute state for the Waybar
# custom/audio-mic widget. Polls on an interval and self-heals if a click
# action's signal poke (see mic-menu.bash/mic-toggle.bash) is ever missed,
# the same as waybar-network-wifi.
default_source=$(@pactl@ get-default-source 2>/dev/null) || default_source=""
sources=$(@pactl@ -f json list sources 2>/dev/null) || sources="[]"
# shellcheck disable=SC2016
source=$(@jq@ --arg name "${default_source}" '[.[] | select(.name == $name)][0] // empty' <<<"${sources}")

if [[ -z ${default_source} || -z ${source} ]]; then
  printf '{"text": "󰍭", "tooltip": "No microphone input available\\nClick to select input", "class": "disabled"}\n'
  exit 0
fi

IFS=$'\t' read -r mute vol_percent desc < <(
  @jq@ -r '[.mute, ([.volume[].value_percent][0] // "0%"), .description] | @tsv' <<<"${source}"
)

if [[ ${mute} == "true" ]]; then
  icon="󰍭"
  class="muted"
  action="Right-click to unmute"
else
  icon="󰍬"
  class="unmuted"
  action="Right-click to mute"
fi

# shellcheck disable=SC2016
@jq@ -cn --arg icon "${icon}" --arg desc "${desc}" --arg vol "${vol_percent}" \
  --arg action "${action}" --arg class "${class}" \
  '{text: $icon, tooltip: ($desc + ": " + $vol + "\nClick to select input\n" + $action), class: $class}'
