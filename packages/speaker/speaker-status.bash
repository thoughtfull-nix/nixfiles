#!@bash@
vol=$(@pactl@ get-sink-volume @DEFAULT_SINK@ |
  head -n1 |
  cut -d'/' -f2 |
  sed 's/ *//g')
if [[ "$(@pactl@ get-sink-mute @DEFAULT_SINK@)" == "Mute: yes" ]]; then
  icon="@volume-mute-icon@"
else
  if [[ (${#vol} -lt 4) && ($vol == "0%" || $vol == "5%" || $vol < "35%") ]]; then
    icon="@volume-low-icon@"
  elif [[ (${#vol} -lt 4) && $vol < "65%" ]]; then
    icon="@volume-med-icon@"
  else
    icon="@volume-high-icon@"
  fi
fi
@notify-send@ -i "${icon}" \
  -a speaker-status \
  --hint=string:x-dunst-stack-tag:speaker-status \
  --hint=string:synchronous:speaker-status \
  --hint=int:value:"${vol%\%}" \
  -t 3000 \
  "${vol}"
