#!@bash@
set -euo pipefail

theme=$(@theme-get@)
if [[ $theme == dark ]]; then
  echo light >~/.config/theme
  @gsettings@ set org.gnome.desktop.interface color-scheme 'prefer-light'
  @pkill@ -USR1 foot || true
  if [[ -f ~/.claude.json ]]; then
    @jq@ '.theme = "light"' ~/.claude.json 2>/dev/null | @sponge@ ~/.claude.json ||
      true
  fi
else
  echo dark >~/.config/theme
  @gsettings@ set org.gnome.desktop.interface color-scheme 'prefer-dark'
  @pkill@ -USR2 foot || true
  if [[ -f ~/.claude.json ]]; then
    @jq@ '.theme = "dark"' ~/.claude.json 2>/dev/null | @sponge@ ~/.claude.json ||
      true
  fi
fi
@theme-sway@
