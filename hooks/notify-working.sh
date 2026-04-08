#!/bin/bash
# ClaudePet Working-State Hook (async, lightweight)
# Fires on ALL tool calls to notify ClaudePet that a session is active.
# Runs async so it never blocks tool execution. No authorization logic.

[ "${CLAUDEPET_CHATTER:-}" = "1" ] && exit 0

INPUT=$(cat)

# Read auth token (if missing, ClaudePet is not running → exit silently)
TOKEN=$(cat "${TMPDIR%/}/claudepet-token" 2>/dev/null) || exit 0

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0

curl -s -m 1 -X POST http://127.0.0.1:23987/working \
  -H "Content-Type: application/json" \
  -H "X-ClaudePet-Token: ${TOKEN}" \
  -d "$(jq -n --arg s "$SESSION_ID" --argjson a true '{session:$s,active:$a}')" >/dev/null 2>&1
