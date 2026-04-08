#!/bin/bash
# ClaudePet Chatter Generator — Ollama (local model)
# Requires: Ollama running on localhost:11434
# Env vars from ClaudePet: CHATTER_PROMPT_PATH, CHATTER_CONTEXT, CHATTER_PERSONA, CHATTER_TIME

set -euo pipefail

# Check Ollama is reachable
curl -s -m 1 http://localhost:11434/api/tags >/dev/null 2>&1 || exit 1

[ -z "${CHATTER_PROMPT_PATH:-}" ] && exit 1
[ ! -f "$CHATTER_PROMPT_PATH" ] && exit 1

SYSTEM_PROMPT=$(cat "$CHATTER_PROMPT_PATH")

USER_MSG="${CHATTER_USER_MSG:-Generate one line of idle chatter in character.}"

# Model (override with CHATTER_OLLAMA_MODEL env var)
MODEL="${CHATTER_OLLAMA_MODEL:-llama3.2:1b}"

RESPONSE=$(curl -s -m 8 http://localhost:11434/api/generate \
  -d "$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --arg prompt "$USER_MSG" \
    '{model: $model, system: $system, prompt: $prompt, stream: false}')" 2>/dev/null)

TEXT=$(echo "$RESPONSE" | jq -r '.response // empty' 2>/dev/null)
[ -n "$TEXT" ] && echo "$TEXT"
