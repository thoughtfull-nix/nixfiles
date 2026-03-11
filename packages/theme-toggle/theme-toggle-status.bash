#!@bash@
set -euo pipefail

theme=$(@theme-get@)
if [[ $theme == dark ]]; then
  echo '󰖔'
else
  echo '󰖙'
fi
