#!/bin/bash
# ClaudePet Chatter Generator — AWS Bedrock
# Requires: aws CLI configured with valid credentials
# Env vars from ClaudePet: CHATTER_PROMPT_PATH, CHATTER_CONTEXT, CHATTER_PERSONA, CHATTER_TIME

set -euo pipefail

command -v aws >/dev/null 2>&1 || exit 1
[ -z "${CHATTER_PROMPT_PATH:-}" ] && exit 1
[ ! -f "$CHATTER_PROMPT_PATH" ] && exit 1

SYSTEM_PROMPT=$(cat "$CHATTER_PROMPT_PATH")

USER_MSG="${CHATTER_USER_MSG:-Generate one line of idle chatter in character.}"

# Model ID (override with CHATTER_BEDROCK_MODEL env var)
MODEL="${CHATTER_BEDROCK_MODEL:-anthropic.claude-3-5-haiku-20251022-v1:0}"
REGION="${AWS_REGION:-us-west-2}"

BODY=$(jq -n \
  --arg system "$SYSTEM_PROMPT" \
  --arg user "$USER_MSG" \
  '{
    anthropic_version: "bedrock-2023-05-31",
    max_tokens: 60,
    system: $system,
    messages: [{role: "user", content: $user}]
  }')

RESPONSE=$(aws bedrock-runtime invoke-model \
  --region "$REGION" \
  --model-id "$MODEL" \
  --content-type "application/json" \
  --accept "application/json" \
  --body "$(echo "$BODY" | base64)" \
  --query 'body' \
  --output text 2>/dev/null | base64 -d 2>/dev/null)

TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null)
[ -n "$TEXT" ] && echo "$TEXT"
