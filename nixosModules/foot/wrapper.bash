#!@bash@
# Wrapper script for foot that applies the current theme on startup
set -euo pipefail

theme=$(@theme-get@)
if [[ $theme == dark ]]; then
  exec @foot@ -o initial-color-theme=2 "$@"
else
  exec @foot@ "$@"
fi
