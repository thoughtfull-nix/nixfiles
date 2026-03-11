#!@bash@
set -euo pipefail

CONFIG_DIR=~/.config/waybar-weather
CACHE_DIR=~/.cache/waybar-weather
LOCATION_FILE="${CONFIG_DIR}/location"
GEOCACHE_FILE="${CACHE_DIR}/location.json"
WEATHER_CACHE_FILE="${CACHE_DIR}/weather.json"
FORECAST_CACHE_FILE="${CACHE_DIR}/forecast.json"
API_KEY_FILE="/run/agenix/openweathermap-api-key"

# Cache TTL: 30 min during day (6am-9pm), 1 hour at night
HOUR=$(date +%H)
if [[ ${HOUR#0} -ge 6 ]] && [[ ${HOUR#0} -lt 21 ]]; then
  CACHE_TTL=1800 # 30 minutes
else
  CACHE_TTL=3600 # 1 hour
fi

# Ensure cache directory exists
mkdir -p "${CACHE_DIR}"

# Read API key
if [[ ! -f ${API_KEY_FILE} ]]; then
  echo "No API key"
  exit 0
fi
API_KEY=$(cat "${API_KEY_FILE}")

# Read location
if [[ ! -f ${LOCATION_FILE} ]]; then
  echo "No location"
  exit 0
fi
LOCATION=$(tr -d '\n' <"${LOCATION_FILE}")

if [[ -z ${LOCATION} ]]; then
  echo "No location"
  exit 0
fi

# Function to get lat/lon from location
geocode() {
  local location="$1"
  local encoded_location
  encoded_location=$(printf '%s' "${location}" | @sed@ 's/ /%20/g; s/,/%2C/g')

  # Check if it looks like a zip code (5 digits)
  if [[ ${location} =~ ^[0-9]{5}$ ]]; then
    @curl@ -sf "https://api.openweathermap.org/geo/1.0/zip?zip=${location},US&appid=${API_KEY}"
  else
    # Use direct geocoding for city names
    local result
    result=$(@curl@ -sf "https://api.openweathermap.org/geo/1.0/direct?q=${encoded_location}&limit=1&appid=${API_KEY}")
    # Extract first result with full location info
    echo "${result}" | @jq@ '.[0] | {lat: .lat, lon: .lon, name: .name, state: .state, country: .country}'
  fi
}

# Check if we need to geocode
need_geocode=false
if [[ ! -f ${GEOCACHE_FILE} ]]; then
  need_geocode=true
else
  cached_query=$(@jq@ -r '.query // empty' "${GEOCACHE_FILE}" 2>/dev/null || echo "")
  if [[ ${cached_query} != "${LOCATION}" ]]; then
    need_geocode=true
  fi
fi

if [[ ${need_geocode} == "true" ]]; then
  geo_result=$(geocode "${LOCATION}")
  if [[ -z ${geo_result} ]] || [[ ${geo_result} == "null" ]]; then
    echo "Geocode failed"
    exit 0
  fi
  # Add query to result for cache invalidation
  # shellcheck disable=SC2016
  echo "${geo_result}" | @jq@ --arg q "${LOCATION}" '. + {query: $q}' >"${GEOCACHE_FILE}"
fi

# Read cached coordinates and location info
LAT=$(@jq@ -r '.lat' "${GEOCACHE_FILE}")
LON=$(@jq@ -r '.lon' "${GEOCACHE_FILE}")
GEO_NAME=$(@jq@ -r '.name // empty' "${GEOCACHE_FILE}")
GEO_STATE=$(@jq@ -r '.state // empty' "${GEOCACHE_FILE}")
GEO_COUNTRY=$(@jq@ -r '.country // empty' "${GEOCACHE_FILE}")

if [[ -z ${LAT} ]] || [[ ${LAT} == "null" ]] || [[ -z ${LON} ]] || [[ ${LON} == "null" ]]; then
  echo "Invalid coords"
  exit 0
fi

# Check if weather cache is stale
need_weather=false
if [[ ! -f ${WEATHER_CACHE_FILE} ]]; then
  need_weather=true
else
  cache_time=$(stat -c %Y "${WEATHER_CACHE_FILE}" 2>/dev/null || echo 0)
  current_time=$(date +%s)
  age=$((current_time - cache_time))
  if [[ ${age} -gt ${CACHE_TTL} ]]; then
    need_weather=true
  fi
fi

if [[ ${need_weather} == "true" ]]; then
  weather_result=$(@curl@ -sf "https://api.openweathermap.org/data/2.5/weather?lat=${LAT}&lon=${LON}&units=imperial&appid=${API_KEY}")
  if [[ -z ${weather_result} ]]; then
    echo "Weather fetch failed"
    exit 0
  fi
  echo "${weather_result}" >"${WEATHER_CACHE_FILE}"

  # Also fetch 5-day forecast
  forecast_result=$(@curl@ -sf "https://api.openweathermap.org/data/2.5/forecast?lat=${LAT}&lon=${LON}&units=imperial&appid=${API_KEY}")
  if [[ -n ${forecast_result} ]]; then
    echo "${forecast_result}" >"${FORECAST_CACHE_FILE}"
  fi
fi

# Parse weather data
WEATHER_MAIN=$(@jq@ -r '.weather[0].main' "${WEATHER_CACHE_FILE}")
TEMP=$(@jq@ -r '.main.temp | round' "${WEATHER_CACHE_FILE}")
FEELS_LIKE=$(@jq@ -r '.main.feels_like | round' "${WEATHER_CACHE_FILE}")
WIND_SPEED=$(@jq@ -r '.wind.speed | round' "${WEATHER_CACHE_FILE}")
WIND_DEG=$(@jq@ -r '.wind.deg // 0' "${WEATHER_CACHE_FILE}")

# Convert wind degrees to direction arrow
# Degrees are meteorological (direction wind comes FROM)
# We show an arrow pointing in the direction wind is going
wind_direction() {
  local deg=$1
  if [[ ${deg} -ge 337 ]] || [[ ${deg} -lt 23 ]]; then
    echo "↓" # N wind blows south
  elif [[ ${deg} -ge 23 ]] && [[ ${deg} -lt 68 ]]; then
    echo "↙" # NE wind blows southwest
  elif [[ ${deg} -ge 68 ]] && [[ ${deg} -lt 113 ]]; then
    echo "←" # E wind blows west
  elif [[ ${deg} -ge 113 ]] && [[ ${deg} -lt 158 ]]; then
    echo "↖" # SE wind blows northwest
  elif [[ ${deg} -ge 158 ]] && [[ ${deg} -lt 203 ]]; then
    echo "↑" # S wind blows north
  elif [[ ${deg} -ge 203 ]] && [[ ${deg} -lt 248 ]]; then
    echo "↗" # SW wind blows northeast
  elif [[ ${deg} -ge 248 ]] && [[ ${deg} -lt 293 ]]; then
    echo "→" # W wind blows east
  else
    echo "↘" # NW wind blows southeast
  fi
}
WIND_DIR=$(wind_direction "${WIND_DEG}")

# Map weather condition to icon (color emoji)
weather_icon() {
  local condition=$1
  case "${condition}" in
    Clear) echo "☀️" ;;
    Clouds) echo "☁️" ;;
    Rain) echo "🌧️" ;;
    Drizzle) echo "🌦️" ;;
    Thunderstorm) echo "⛈️" ;;
    Snow) echo "❄️" ;;
    Mist | Fog | Haze | Smoke | Dust | Sand | Ash | Squall | Tornado) echo "🌫️" ;;
    *) echo "☁️" ;;
  esac
}
ICON=$(weather_icon "${WEATHER_MAIN}")

# Build full location string
FULL_LOCATION="${GEO_NAME}"
[[ -n ${GEO_STATE} ]] && FULL_LOCATION="${FULL_LOCATION}, ${GEO_STATE}"
[[ -n ${GEO_COUNTRY} ]] && FULL_LOCATION="${FULL_LOCATION}, ${GEO_COUNTRY}"
FULL_LOCATION="${FULL_LOCATION} (${LAT}, ${LON})"

# Build 5-day forecast table using Pango markup
FORECAST_TABLE=""
if [[ -f ${FORECAST_CACHE_FILE} ]]; then
  # Get today's date to skip it
  TODAY=$(date +%Y-%m-%d)

  # Parse forecast: group by date, get high/low temps and most common weather condition
  # jq outputs: date|high|low|condition for each of next 5 days
  # shellcheck disable=SC2016
  FORECAST_DATA=$(@jq@ -r --arg today "${TODAY}" '
    .list
    | map(select((.dt_txt | split(" ")[0]) != $today))
    | group_by(.dt_txt | split(" ")[0])
    | .[0:5]
    | map({
        date: .[0].dt_txt | split(" ")[0],
        high: [.[].main.temp_max] | max | round,
        low: [.[].main.temp_min] | min | round,
        condition: (group_by(.weather[0].main) | max_by(length) | .[0].weather[0].main)
      })
    | .[]
    | "\(.date)|\(.high)|\(.low)|\(.condition)"
  ' "${FORECAST_CACHE_FILE}" 2>/dev/null || echo "")

  if [[ -n ${FORECAST_DATA} ]]; then
    # Build three rows: icons, day/date, temps
    ROW_ICONS=""
    ROW_DAYS=""
    ROW_TEMPS=""
    COL_WIDTH=11

    while IFS='|' read -r date high low condition; do
      icon=$(weather_icon "${condition}")
      day_name=$(date -d "${date}" +%a)
      month_day=$(date -d "${date}" +%-m/%-d)

      # Icons row (emoji takes ~2 char width, pad rest)
      ROW_ICONS="${ROW_ICONS}${icon}$(printf '%*s' $((COL_WIDTH - 2)) '')"
      # Day/date row
      day_date="${day_name} ${month_day}"
      ROW_DAYS="${ROW_DAYS}$(printf "%-${COL_WIDTH}s" "${day_date}")"
      # Temps row (COL_WIDTH + 1 because °F is also 2 char width like emoji)
      temps="${high}/${low}°F"
      ROW_TEMPS="${ROW_TEMPS}$(printf "%-$((COL_WIDTH + 1))s" "${temps}")"
    done <<<"${FORECAST_DATA}"

    # Use monospace font for alignment
    FORECAST_TABLE="<tt>${ROW_ICONS}
${ROW_DAYS}
${ROW_TEMPS}</tt>"
  fi
fi

# Output JSON for waybar
TEXT="${ICON} ${TEMP}°F (${FEELS_LIKE}°F) ${WIND_DIR}${WIND_SPEED}mph"
HINT="<small>Right-click to change location</small>"
if [[ -n ${FORECAST_TABLE} ]]; then
  TOOLTIP="${FULL_LOCATION}
${HINT}

${FORECAST_TABLE}"
else
  TOOLTIP="${FULL_LOCATION}
${HINT}"
fi
# shellcheck disable=SC2016
@jq@ -nc --arg text "${TEXT}" --arg tooltip "${TOOLTIP}" '{text: $text, tooltip: $tooltip}'
