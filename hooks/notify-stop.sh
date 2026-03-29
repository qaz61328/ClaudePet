#!/bin/bash
# ClaudePet Stop Hook
# Called when Claude Code finishes work, notifies the desktop pet
# Falls back silently if ClaudePet is not running

INPUT=$(cat)

eval "$(echo "$INPUT" | jq -r '@sh "CWD=\(.cwd // "unknown") SESSION_ID=\(.session_id // "")"')"
PROJECT=$(basename "$CWD")

# End working state first (must happen before chatter lock check, otherwise stuck in working animation)
if [ -n "$SESSION_ID" ]; then
  curl -s -m 1 -X POST http://127.0.0.1:23987/working \
    -H "Content-Type: application/json" \
    -d "{\"session\":\"${SESSION_ID}\",\"active\":false}" >/dev/null 2>&1
fi

# Idle chatter lock: cron-triggered chatter sessions don't need a "work complete" notification
CHATTER_LOCK="/tmp/claudepet-chatter-lock"
if [ -f "$CHATTER_LOCK" ]; then
    rm -f "$CHATTER_LOCK"
    exit 0
fi

# Try to notify ClaudePet
RESPONSE=$(curl -s -m 3 -X POST http://127.0.0.1:23987/notify \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"stop\",\"project\":\"${PROJECT:-unknown}\"}" 2>/dev/null)

# curl failure → silently ignore (no notification if ClaudePet is not running)
