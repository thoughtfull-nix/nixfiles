#!@bash@
set -euo pipefail

CONFIG_DIR=~/.config/waybar-weather
CACHE_DIR=~/.cache/waybar-weather
LOCATION_FILE="${CONFIG_DIR}/location"

# Ensure config directory exists
mkdir -p "${CONFIG_DIR}"

# Create location file if it doesn't exist
if [[ ! -f ${LOCATION_FILE} ]]; then
  echo "New York, New York, US" >"${LOCATION_FILE}"
fi

# Open location file in emacsclient (blocking)
@emacsclient@ "${LOCATION_FILE}"

# Clear cache after editor closes
rm -rf "${CACHE_DIR:?}"/*
