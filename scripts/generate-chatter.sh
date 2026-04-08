#!/bin/bash
# ClaudePet Chatter Generator — Auto-detect provider
# Tries providers in order: Anthropic-compatible API → AWS Bedrock → Claude Code CLI
# Env vars from ClaudePet: CHATTER_PROMPT_PATH, CHATTER_CONTEXT, CHATTER_PERSONA, CHATTER_TIME

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"

# Override auto-detection: CHATTER_PROVIDER=anthropic|bedrock|claude-cli
if [ -n "${CHATTER_PROVIDER:-}" ]; then
  case "$CHATTER_PROVIDER" in
    anthropic)  FORCED_SCRIPT="$SCRIPT_DIR/chatter-anthropic.sh" ;;
    bedrock)    FORCED_SCRIPT="$SCRIPT_DIR/chatter-bedrock.sh" ;;
    claude-cli) FORCED_SCRIPT="$SCRIPT_DIR/chatter-claude-cli.sh" ;;
    *) echo "Unknown CHATTER_PROVIDER: $CHATTER_PROVIDER" >&2; exit 1 ;;
  esac
fi

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

# If provider is forced, skip auto-detection
[ -n "${FORCED_SCRIPT:-}" ] && exec "$FORCED_SCRIPT"

# 1. Anthropic API key (direct)
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  exec "$SCRIPT_DIR/chatter-anthropic.sh"
fi

# 2. Anthropic auth token (company proxy / Bedrock-via-proxy)
if [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  exec "$SCRIPT_DIR/chatter-anthropic.sh"
fi

# 3. Check ~/.claude/settings.json for Anthropic credentials (single jq call, export for provider script)
if [ -f "$SETTINGS" ]; then
  _settings=$(jq -r '[
    (.env.ANTHROPIC_AUTH_TOKEN // ""),
    (.env.ANTHROPIC_BASE_URL // ""),
    (.env.ANTHROPIC_DEFAULT_HAIKU_MODEL // .env.ANTHROPIC_DEFAULT_SONNET_MODEL // ""),
    (.env.ANTHROPIC_API_KEY // "")
  ] | join("\t")' "$SETTINGS" 2>/dev/null) || _settings=""
  IFS=$'\t' read -r _token _base _model _key <<< "$_settings"
  if [ -n "$_token" ]; then
    export ANTHROPIC_AUTH_TOKEN="$_token"
    [ -n "$_base" ] && export ANTHROPIC_BASE_URL="$_base"
    [ -n "$_model" ] && export ANTHROPIC_MODEL="$_model"
    exec "$SCRIPT_DIR/chatter-anthropic.sh"
  fi
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

# 5. Claude Code CLI (--print --bare fallback, covers all CC users)
if command -v claude >/dev/null 2>&1; then
  exec "$SCRIPT_DIR/chatter-claude-cli.sh"
fi

# No provider available
exit 1
