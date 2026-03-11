#!@bash@
val=$(@brightnessctl@ -m | @cut@ -d, -f4)
if [[ (${#val} -lt 4) && ($val == "0%" || $val == "5%" || $val < "35%") ]]; then
  icon="@brightness-low-icon@"
elif [[ (${#val} -lt 4) && $val < "65%" ]]; then
  icon="@brightness-med-icon@"
else
  icon="@brightness-high-icon@"
fi
@notify-send@ -i "${icon}" \
  -a brightness-status \
  --hint=string:x-dunst-stack-tag:brightness-status \
  --hint=string:synchronous:brightness-status \
  --hint=int:value:"${val%\%}" \
  -t 3000 \
  "${val}"
