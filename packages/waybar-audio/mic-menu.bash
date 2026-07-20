#!@bash@
set -euo pipefail

# Fuzzel-driven picker for the Waybar custom/audio-mic widget's primary
# click. Lists every input device (source), excluding sink monitors (a
# monitor's "monitor_source" property points back at the sink it came from;
# a real input device's is empty) -- those aren't microphones and pactl
# itself would reject them as a set-default-source target. Once a source is
# chosen, both sets it as the default *and* re-routes every currently
# recording stream to it, matching the sink/speaker side of this widget.
sources=$(@pactl@ -f json list sources 2>/dev/null) || sources="[]"
sources=$(@jq@ -c '[.[] | select(.monitor_source == "")]' <<<"${sources}")
mapfile -t names < <(@jq@ -r '.[].name' <<<"${sources}")
mapfile -t descriptions < <(@jq@ -r '.[].description' <<<"${sources}")

((${#names[@]} == 0)) && exit 0

# See speaker-menu.bash/wifi-menu.bash for why a cancelled fuzzel must not
# trip errexit here.
index=$(printf '%s\n' "${descriptions[@]}" | @fuzzel@ --dmenu --minimal-lines --placeholder "Select input" --index) || exit 0
[[ -z ${index} ]] && exit 0

selected="${names[index]}"
@pactl@ set-default-source "${selected}"

mapfile -t outputs < <(@pactl@ list source-outputs short | cut -f1)
for output in "${outputs[@]}"; do
  [[ -z ${output} ]] && continue
  @pactl@ move-source-output "${output}" "${selected}" || true
done

# See kanshi-active.bash for why this signals the unit rather than pkill -x waybar.
@systemctl@ --user kill --signal=RTMIN+7 waybar.service || true
