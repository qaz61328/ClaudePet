#!/bin/bash
# ClaudePet Stop Hook
# Called when Claude Code finishes work, notifies the desktop pet
# Falls back silently if ClaudePet is not running

INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
PROJECT=$(basename "$CWD")

# Read auth token (if missing, ClaudePet is not running → fall through silently)
TOKEN_FILE="${TMPDIR%/}/claudepet-token"
TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null) || exit 0

# End working state first (must happen before chatter lock check, otherwise stuck in working animation)
if [ -n "$SESSION_ID" ]; then
  curl -s -m 1 -X POST http://127.0.0.1:23987/working \
    -H "Content-Type: application/json" \
    -H "X-ClaudePet-Token: ${TOKEN}" \
    -d "$(jq -n --arg s "$SESSION_ID" --argjson a false '{session:$s,active:$a}')" >/dev/null 2>&1
fi

# Idle chatter lock: cron-triggered chatter sessions don't need a "work complete" notification
# Use time-based check instead of delete-on-first-read to handle multiple Stop events
CHATTER_LOCK="${TMPDIR%/}/claudepet-chatter-lock"
if [ -f "$CHATTER_LOCK" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$CHATTER_LOCK") ))
    if [ "$LOCK_AGE" -lt 60 ]; then
        # Recent lock → chatter session still in progress, skip notification
        exit 0
    else
        # Stale lock → clean up and proceed with notification
        rm -f "$CHATTER_LOCK"
    fi
fi

# Try to notify ClaudePet
RESPONSE=$(curl -s -m 3 -X POST http://127.0.0.1:23987/notify \
  -H "Content-Type: application/json" \
  -H "X-ClaudePet-Token: ${TOKEN}" \
  -d "$(jq -n --arg t "stop" --arg p "${PROJECT:-unknown}" '{type:$t,project:$p}')" 2>/dev/null)

# curl failure → silently ignore (no notification if ClaudePet is not running)
