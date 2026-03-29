#!/bin/bash
# ClaudePet PreToolUse Hook
# Called when Claude Code needs authorization, synchronously waits for user decision
# On failure/timeout → no output, lets Claude Code fall through to normal flow

INPUT=$(cat)

eval "$(echo "$INPUT" | jq -r '@sh "CWD=\(.cwd // "unknown") TOOL=\(.tool_name // "unknown") SESSION_ID=\(.session_id // "")"')"
PROJECT=$(basename "$CWD")

SESSION_ALLOW="/tmp/claudepet-session-allow"

# Notify ClaudePet this session is active (non-blocking fire-and-forget)
if [ -n "$SESSION_ID" ]; then
  curl -s -m 1 -X POST http://127.0.0.1:23987/working \
    -H "Content-Type: application/json" \
    -d "{\"session\":\"${SESSION_ID}\",\"active\":true}" >/dev/null 2>&1 &
fi

# AskUserQuestion → notify user to check back, skip authorization flow
if [ "$TOOL" = "AskUserQuestion" ]; then
  curl -s -m 3 -X POST http://127.0.0.1:23987/notify \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"ask\",\"project\":\"${PROJECT}\"}" >/dev/null 2>&1
  exit 0
fi

# ExitPlanMode → Plan Mode plan ready notification, skip authorization flow
if [ "$TOOL" = "ExitPlanMode" ]; then
  curl -s -m 3 -X POST http://127.0.0.1:23987/notify \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"plan\",\"project\":\"${PROJECT}\"}" >/dev/null 2>&1
  exit 0
fi

# Tool already in "always allow" list → pass through, no bubble
if [ -f "$SESSION_ALLOW" ] && grep -qx "$TOOL" "$SESSION_ALLOW"; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
fi

# Extract fields expected by the server from tool_input
COMMAND=""
DESCRIPTION=""
FILE_PATH=""

case "$TOOL" in
  Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    DESCRIPTION=$(echo "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null)
    if [ ${#COMMAND} -gt 500 ]; then
      COMMAND="${COMMAND:0:497}..."
    fi
    ;;
  Edit|Write)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    ;;
  NotebookEdit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.notebook_path // ""' 2>/dev/null)
    ;;
esac

# Build authorize JSON payload (using jq for safe assembly, prevents injection)
PAYLOAD=$(jq -n \
  --arg tool "$TOOL" \
  --arg project "$PROJECT" \
  --arg command "${COMMAND:-}" \
  --arg description "${DESCRIPTION:-}" \
  --arg file_path "${FILE_PATH:-}" \
  '{tool: $tool, project: $project}
   + (if $command != "" then {command: $command} else {} end)
   + (if $description != "" then {description: $description} else {} end)
   + (if $file_path != "" then {file_path: $file_path} else {} end)')

# Synchronously wait for ClaudePet response
RESPONSE=$(curl -s -m 60 -X POST http://127.0.0.1:23987/authorize \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
  DECISION=$(echo "$RESPONSE" | jq -r '.decision // ""' 2>/dev/null)

  # "Always allow" → remember this tool, skip next time
  if [ "$DECISION" = "approve_session" ]; then
    RESP_TOOL=$(echo "$RESPONSE" | jq -r '.tool // ""' 2>/dev/null)
    [ -n "$RESP_TOOL" ] && echo "$RESP_TOOL" >> "$SESSION_ALLOW"
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
  fi

  # approve → allow, deny → deny
  if [ "$DECISION" = "approve" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  elif [ "$DECISION" = "deny" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"User denied"}}'
  fi
  exit 0
fi

# ClaudePet not running → silently ignore, don't block
exit 0
