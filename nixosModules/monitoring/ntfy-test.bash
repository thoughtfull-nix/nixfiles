#!/usr/bin/env bash
set -euo pipefail

MESSAGE="${1:-This is only a test}"

ntfy publish --title "Test message" --tags rotating_light "@ntfyServer@/@ntfyTopic@" "${MESSAGE}"
