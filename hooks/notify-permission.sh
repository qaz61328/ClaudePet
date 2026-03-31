#!/bin/bash
# ClaudePet PreToolUse Hook
# Called when Claude Code needs authorization, synchronously waits for user decision
# On failure/timeout → no output, lets Claude Code fall through to normal flow

INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
PROJECT=$(basename "$CWD")

# Read auth token (if missing, ClaudePet is not running → fall through silently)
TOKEN_FILE="${TMPDIR%/}/claudepet-token"
TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null) || exit 0

# Per-project session-allow file (CWD hash prevents cross-project leaking)
PROJECT_HASH=$(echo -n "$CWD" | md5 -q)
SESSION_ALLOW="${TMPDIR%/}/claudepet-session-allow-${PROJECT_HASH}"

# Notify ClaudePet this session is active (non-blocking fire-and-forget)
if [ -n "$SESSION_ID" ]; then
  curl -s -m 1 -X POST http://127.0.0.1:23987/working \
    -H "Content-Type: application/json" \
    -H "X-ClaudePet-Token: ${TOKEN}" \
    -d "$(jq -n --arg s "$SESSION_ID" --argjson a true '{session:$s,active:$a}')" >/dev/null 2>&1 &
fi

# AskUserQuestion → notify user to check back, skip authorization flow
if [ "$TOOL" = "AskUserQuestion" ]; then
  curl -s -m 3 -X POST http://127.0.0.1:23987/notify \
    -H "Content-Type: application/json" \
    -H "X-ClaudePet-Token: ${TOKEN}" \
    -d "$(jq -n --arg t "ask" --arg p "$PROJECT" '{type:$t,project:$p}')" >/dev/null 2>&1
  exit 0
fi

# ExitPlanMode → Plan Mode plan ready notification, skip authorization flow
if [ "$TOOL" = "ExitPlanMode" ]; then
  curl -s -m 3 -X POST http://127.0.0.1:23987/notify \
    -H "Content-Type: application/json" \
    -H "X-ClaudePet-Token: ${TOKEN}" \
    -d "$(jq -n --arg t "plan" --arg p "$PROJECT" '{type:$t,project:$p}')" >/dev/null 2>&1
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
TOOL_ARG=""

case "$TOOL" in
  Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    DESCRIPTION=$(echo "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null)
    TOOL_ARG="$COMMAND"
    if [ ${#COMMAND} -gt 500 ]; then
      COMMAND="${COMMAND:0:497}..."
    fi
    ;;
  Read|Edit|Write)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    TOOL_ARG="$FILE_PATH"
    ;;
  NotebookEdit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.notebook_path // ""' 2>/dev/null)
    TOOL_ARG="$FILE_PATH"
    ;;
  mcp__*)
    # MCP tools: extract key parameters as description for auth bubble display
    DESCRIPTION=$(echo "$INPUT" | jq -r '[.tool_input | to_entries[] | select(.value | type == "string" or type == "number" or type == "boolean") | "\(.key): \(.value)"] | .[0:3] | join(", ")' 2>/dev/null)
    if [ ${#DESCRIPTION} -gt 80 ]; then
      DESCRIPTION="${DESCRIPTION:0:77}..."
    fi
    ;;
esac

# Auto-allowed by Claude Code permissions.allow → pass through silently (no bubble)
is_auto_allowed() {
  local tool="$1"
  local arg="$2"
  for settings in "$HOME/.claude/settings.json" "$CWD/.claude/settings.json" "$CWD/.claude/settings.local.json"; do
    [ -f "$settings" ] || continue
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      if [ "$pattern" = "$tool" ]; then return 0; fi
      if [[ "$pattern" == "$tool("*")" ]]; then
        local glob="${pattern#${tool}(}"
        glob="${glob%)}"
        if [[ -n "$arg" && "$arg" == $glob ]]; then return 0; fi
      fi
    done < <(jq -r '.permissions.allow[]? // empty' "$settings" 2>/dev/null)
  done
  return 1
}

if is_auto_allowed "$TOOL" "$TOOL_ARG"; then
  exit 0
fi

# "Authorize in Terminal" mode → notify pet and let Claude Code handle authorization natively
if [ -f "${TMPDIR%/}/claudepet-passthrough-auth" ]; then
  curl -s -m 3 -X POST http://127.0.0.1:23987/notify \
    -H "Content-Type: application/json" \
    -H "X-ClaudePet-Token: ${TOKEN}" \
    -d "$(jq -n --arg t "terminalAuth" --arg p "$PROJECT" '{type:$t,project:$p}')" >/dev/null 2>&1
  exit 0
fi

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
  -H "X-ClaudePet-Token: ${TOKEN}" \
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
