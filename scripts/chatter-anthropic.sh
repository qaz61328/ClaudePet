#!/bin/bash
# ClaudePet Chatter Generator — Anthropic-compatible API
# Supports: ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN, or auto-read from ~/.claude/settings.json
# Env vars from ClaudePet: CHATTER_PROMPT_PATH, CHATTER_CONTEXT, CHATTER_PERSONA, CHATTER_TIME

set -euo pipefail

[ -z "${CHATTER_PROMPT_PATH:-}" ] && exit 1
[ ! -f "$CHATTER_PROMPT_PATH" ] && exit 1

# Credentials are expected in env vars, exported by generate-chatter.sh
# (ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN, plus optional ANTHROPIC_BASE_URL/ANTHROPIC_MODEL)

# Determine auth header
AUTH_HEADER=""
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  AUTH_HEADER="x-api-key: ${ANTHROPIC_API_KEY}"
elif [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  AUTH_HEADER="Authorization: Bearer ${ANTHROPIC_AUTH_TOKEN}"
else
  exit 1
fi

# Determine base URL and model
BASE_URL="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
BASE_URL="${BASE_URL%/}"
MODEL="${CHATTER_MODEL:-${ANTHROPIC_MODEL:-claude-haiku-4-5-20251001}}"

SYSTEM_PROMPT=$(cat "$CHATTER_PROMPT_PATH")

USER_MSG="${CHATTER_USER_MSG:-Generate one line of idle chatter in character.}"

RESPONSE=$(curl -s -m 8 "${BASE_URL}/v1/messages" \
  -H "${AUTH_HEADER}" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$(jq -n \
    --arg system "$SYSTEM_PROMPT" \
    --arg user "$USER_MSG" \
    --arg model "$MODEL" \
    '{
      model: $model,
      max_tokens: 60,
      system: $system,
      messages: [{role: "user", content: $user}]
    }')" 2>/dev/null)

# Extract text from response
TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null)
[ -n "$TEXT" ] && echo "$TEXT"
