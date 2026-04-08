#!/bin/bash
# ClaudePet Chatter Generator — Claude Code CLI (--print --bare)
# Fallback provider for users without a standalone API key.
# Uses the user's existing Claude Code authentication.
# Env vars: CHATTER_PROMPT_PATH (system prompt file), CHATTER_USER_MSG (pre-built user message)

set -euo pipefail

[ -z "${CHATTER_PROMPT_PATH:-}" ] && exit 1
[ ! -f "$CHATTER_PROMPT_PATH" ] && exit 1

command -v claude >/dev/null 2>&1 || exit 1

USER_MSG="${CHATTER_USER_MSG:-Generate one line of idle chatter in character.}"

RAW=$(echo "$USER_MSG" \
  | claude -p --bare --system-prompt-file "$CHATTER_PROMPT_PATH" 2>/dev/null)

# Strip leading/trailing whitespace, take first non-empty line
TEXT=$(echo "$RAW" | sed '/^[[:space:]]*$/d' | head -1)
[ -n "$TEXT" ] && echo "$TEXT"
