#!/usr/bin/env bash
set -euo pipefail

# Get human-readable description from systemd
DESCRIPTION=$(@systemctl@ show -p Description "${UNIT}" | cut -d= -f2-)

MESSAGE="${DESCRIPTION} failed on ${HOST}

\`\`\`
$(SYSTEMD_COLORS=0 @systemctl@ --no-pager status "${UNIT}" 2>&1 || true)
\`\`\`"

@curl@ \
  -H "Title: ${DESCRIPTION} failed" \
  -H "Priority: high" \
  -H "Tags: x" \
  -H "Markdown: yes" \
  -d "${MESSAGE}" \
  @ntfyServer@/@ntfyTopic@
