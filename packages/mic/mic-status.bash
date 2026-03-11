#!/usr/bin/env bash
vol=$(@pactl@ get-source-volume @DEFAULT_SOURCE@ |
  head -n1 |
  cut -d'/' -f2 |
  sed 's/ *//g')
if [[ "$(@pactl@ get-source-mute @DEFAULT_SOURCE@)" == "Mute: yes" ]]; then
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
  -a mic-status \
  --hint=string:x-dunst-stack-tag:mic-status \
  --hint=string:synchronous:mic-status \
  --hint=int:value:"${vol%\%}" \
  -t 3000 \
  "${vol}"
