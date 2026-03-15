#!/usr/bin/env bash
set -euo pipefail

model="@model@"
if [[ -z "$model" ]]; then
  @notify-send@ -a dictation \
    -t 0 \
    --category=no-sound \
    --hint=string:x-dunst-stack-tag:dictation \
    --hint=string:synchronous:dictation \
    "Dictation" "Error: no model file configured"
  exit 1
fi

# Runtime directory for storing state
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
pidfile="$runtime_dir/dictation.pid"
wavfile="$runtime_dir/dictation.wav"

mode="${1:-toggle}"

case "$mode" in
  start)
    # Start recording
    if [[ -f "$pidfile" ]]; then
      exit 0  # Already recording
    fi

    # Play start sound
    @play@ -q @start-sound@ &

    @notify-send@ -a dictation \
      -t 0 \
      --category=no-sound \
      --hint=string:x-dunst-stack-tag:dictation \
      --hint=string:synchronous:dictation \
      "Dictation" "Recording..."

    # Start recording in background and save PID
    # --buffer 1024: smaller buffer for lower latency
    # Use ALSA directly for lower latency (bypass PulseAudio)
    AUDIODRIVER=alsa @recbin@ --buffer 1024 -t wav "$wavfile" &
    echo $! > "$pidfile"
    ;;

  stop)
    # Stop recording and transcribe
    if [[ ! -f "$pidfile" ]]; then
      exit 0  # Not recording
    fi

    # Stop the recording process
    pid=$(cat "$pidfile")
    # Small delay to let audio pipeline flush into sox's buffer
    sleep 0.3
    kill -s INT "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm "$pidfile"

    # Check if we have a recording
    if [[ ! -f "$wavfile" ]] || [[ ! -s "$wavfile" ]]; then
      @play@ -q @cancel-sound@ &
      @notify-send@ -a dictation \
        -t 3000 \
        --category=no-sound \
        --hint=string:x-dunst-stack-tag:dictation \
        --hint=string:synchronous:dictation \
        "Dictation" "No audio recorded"
      rm -f "$wavfile"
      exit 0
    fi

    @notify-send@ -a dictation \
      -t 0 \
      --category=no-sound \
      --hint=string:x-dunst-stack-tag:dictation \
      --hint=string:synchronous:dictation \
      "Dictation" "Transcribing..."

    # Transcribe with whisper-cpp
    # --max-len 0: no limit on segment length
    # --max-tokens 0: no limit on tokens per segment
    @whisper@ --model "$model" --output-txt "$wavfile"

    result_file="${wavfile}.txt"
    if [[ -f "$result_file" ]]; then
      # Filter whisper metadata markers (e.g. [BLANK_AUDIO], [MUSIC])
      filtered=$(grep -v '^\[' "$result_file")
      # Remove blank lines and leading/trailing whitespace per line
      trimmed=$(echo "$filtered" | sed '/^[[:space:]]*$/d;s/^[[:space:]]*//;s/[[:space:]]*$//')
      # Join lines into a single string
      result=$(echo "$trimmed" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
      if [[ -n "$result" ]]; then
        @wtype@ "$result"
        @notify-send@ -a dictation \
          -t 3000 \
          --category=no-sound \
          --hint=string:x-dunst-stack-tag:dictation \
          --hint=string:synchronous:dictation \
          "Dictation" "Done"
      else
        @play@ -q @cancel-sound@ &
        @notify-send@ -a dictation \
          -t 3000 \
          --category=no-sound \
          --hint=string:x-dunst-stack-tag:dictation \
          --hint=string:synchronous:dictation \
          "Dictation" "No speech detected"
      fi
    fi

    # Clean up
    rm -f "$wavfile" "$result_file"
    ;;

  *)
    echo "Usage: $0 {start|stop}"
    exit 1
    ;;
esac
