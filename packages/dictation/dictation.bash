#!/usr/bin/env bash
set -euo pipefail

model="@model@"
if [[ -z "$model" ]]; then
  @notify-send@ -t 3000 \
    -h string:x-dunst-stack-tag:dictation \
    "Dictation" "Error: no model file configured"
  exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

wav="$tmpdir/recording.wav"
@notify-send@ -t 30000 \
  -h string:x-dunst-stack-tag:dictation \
  "Dictation" "Recording..."

# Record until 2 seconds of silence (stop when volume < 3% for 2s)
# Parameters: above-periods above-duration above-threshold below-periods below-duration below-threshold
# - Start when audio is above 3% for 0.1s, stop when below 3% for 2s
@rec@ -t wav "$wav" silence 1 0.1 3% 1 2.0 3%

@notify-send@ -t 10000 \
  -h string:x-dunst-stack-tag:dictation \
  "Dictation" "Transcribing..."

# Transcribe with whisper-cpp
@whisper-cpp@ --model "$model" --output-txt --output-dir "$tmpdir" "$wav"

result_file="$tmpdir/recording.txt"
if [[ -f "$result_file" ]]; then
  # Filter whisper-cpp metadata markers (e.g. [BLANK_AUDIO], [MUSIC])
  filtered=$(grep -v '^\[' "$result_file")
  # Remove blank lines and leading/trailing whitespace per line
  trimmed=$(echo "$filtered" | sed '/^[[:space:]]*$/d;s/^[[:space:]]*//;s/[[:space:]]*$//')
  # Join lines into a single string
  result=$(echo "$trimmed" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  if [[ -n "$result" ]]; then
    @wtype@ "$result"
    @notify-send@ -t 5000 \
      -h string:x-dunst-stack-tag:dictation \
      "Dictation" "$result"
  else
    @notify-send@ -t 3000 \
      -h string:x-dunst-stack-tag:dictation \
      "Dictation" "No speech detected"
  fi
fi
