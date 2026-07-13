#!/usr/bin/env bash
set -euo pipefail

# Get human-readable description from systemd
DESCRIPTION=$(@systemctl@ show -p Description "${UNIT}" | cut -d= -f2-)

MESSAGE="${DESCRIPTION} failed on ${HOST}

\`\`\`
$(SYSTEMD_COLORS=0 @systemctl@ --no-pager status "${UNIT}" 2>&1 || true)
\`\`\`"

@ntfy@ publish \
  --title "${DESCRIPTION} failed" \
  --priority high \
  --tags x \
  --markdown \
  "@ntfyServer@/@ntfyTopic@" \
  "${MESSAGE}"
