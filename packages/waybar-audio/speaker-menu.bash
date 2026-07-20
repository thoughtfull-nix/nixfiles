#!@bash@
set -euo pipefail

# Fuzzel-driven picker for the Waybar custom/audio-speaker widget's primary
# click. Lists every output device (sink) and, once one is chosen, both sets
# it as the default *and* re-routes every currently-playing stream to it --
# matching pavucontrol/GNOME's output-device picker, where switching output
# while something is already playing actually moves the sound instead of
# only affecting streams that start afterward.
sinks=$(@pactl@ -f json list sinks 2>/dev/null) || sinks="[]"
mapfile -t names < <(@jq@ -r '.[].name' <<<"${sinks}")
mapfile -t descriptions < <(@jq@ -r '.[].description' <<<"${sinks}")

((${#names[@]} == 0)) && exit 0

# fuzzel exits non-zero (2 on Escape/right-click, 1 if dmenu mode never got
# a selection) whenever nothing was chosen, which `errexit` would otherwise
# treat as a script failure right at the assignment -- see wifi-menu.bash.
index=$(printf '%s\n' "${descriptions[@]}" | @fuzzel@ --dmenu --minimal-lines --placeholder "Select output" --index) || exit 0
[[ -z ${index} ]] && exit 0

selected="${names[index]}"
@pactl@ set-default-sink "${selected}"

mapfile -t inputs < <(@pactl@ list sink-inputs short | cut -f1)
for input in "${inputs[@]}"; do
  [[ -z ${input} ]] && continue
  @pactl@ move-sink-input "${input}" "${selected}" || true
done

# Signal the systemd unit directly rather than matching the process by name:
# Nix wraps the waybar binary (for GTK/GIO env vars), so the actual running
# process is named ".waybar-wrapped" on disk -- see kanshi-active.bash.
@systemctl@ --user kill --signal=RTMIN+6 waybar.service || true
