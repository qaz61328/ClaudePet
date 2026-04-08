#!/bin/bash
# ClaudePet Chatter Generator — Auto-detect provider
# Tries providers in order: Anthropic-compatible API → AWS Bedrock → Ollama
# Env vars from ClaudePet: CHATTER_PROMPT_PATH, CHATTER_CONTEXT, CHATTER_PERSONA, CHATTER_TIME

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"

# Build user message once (all provider scripts use CHATTER_USER_MSG)
CHATTER_USER_MSG="Current time: ${CHATTER_TIME:-unknown}"
if [ -n "${CHATTER_CONTEXT:-}" ]; then
  CHATTER_USER_MSG="${CHATTER_USER_MSG}\nRecent work: ${CHATTER_CONTEXT}"
fi
if [ -n "${CHATTER_RECENT:-}" ]; then
  CHATTER_USER_MSG="${CHATTER_USER_MSG}\nRecent chatter (do NOT repeat these): ${CHATTER_RECENT}"
fi
CHATTER_USER_MSG="${CHATTER_USER_MSG}\n\nGenerate one line of idle chatter in character."
export CHATTER_USER_MSG

# 1. Anthropic API key (direct)
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  exec "$SCRIPT_DIR/chatter-anthropic.sh"
fi

# 2. Anthropic auth token (company proxy / Bedrock-via-proxy)
if [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  exec "$SCRIPT_DIR/chatter-anthropic.sh"
fi

# 3. Check ~/.claude/settings.json for Anthropic credentials (export so provider script skips re-read)
if [ -f "$SETTINGS" ]; then
  _token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN // empty' "$SETTINGS" 2>/dev/null)
  if [ -n "$_token" ]; then
    export ANTHROPIC_AUTH_TOKEN="$_token"
    _base=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$SETTINGS" 2>/dev/null)
    [ -n "$_base" ] && export ANTHROPIC_BASE_URL="$_base"
    _model=$(jq -r '.env.ANTHROPIC_DEFAULT_HAIKU_MODEL // .env.ANTHROPIC_DEFAULT_SONNET_MODEL // empty' "$SETTINGS" 2>/dev/null)
    [ -n "$_model" ] && export ANTHROPIC_MODEL="$_model"
    exec "$SCRIPT_DIR/chatter-anthropic.sh"
  fi
  _key=$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$SETTINGS" 2>/dev/null)
  if [ -n "$_key" ]; then
    export ANTHROPIC_API_KEY="$_key"
    exec "$SCRIPT_DIR/chatter-anthropic.sh"
  fi
fi

# 4. AWS Bedrock (check aws CLI + local credentials before live STS call)
if command -v aws >/dev/null 2>&1; then
  if [ -n "${AWS_ACCESS_KEY_ID:-}" ] || [ -f "$HOME/.aws/credentials" ] || [ -f "$HOME/.aws/config" ]; then
    exec "$SCRIPT_DIR/chatter-bedrock.sh"
  fi
fi

# 5. Ollama (local)
if curl -s -m 1 http://localhost:11434/api/tags >/dev/null 2>&1; then
  exec "$SCRIPT_DIR/chatter-ollama.sh"
fi

# No provider available
exit 1
