#!/bin/bash
# ClaudePet Upgrade Script
# Rebuild + update configs + restart. Run after git pull.
# Usage: bash scripts/upgrade.sh

set -euo pipefail

# ── Colors ────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# ── Project path (derived from script location) ──────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; exit 1; }

# ── Prerequisites ─────────────────────────────────────
if ! command -v jq &>/dev/null; then
  fail "jq is required. Install: brew install jq"
fi

# ══════════════════════════════════════════════════════
VERSION=$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "unknown")
printf "\n${BOLD}ClaudePet Upgrade → v%s${NC}\n" "$VERSION"
printf "Project: %s\n\n" "$PROJECT_DIR"

# ══════════════════════════════════════════════════════
# Step 1: Build
# ══════════════════════════════════════════════════════
printf "${BOLD}[1/4] Building release binary...${NC}\n"
if (cd "$PROJECT_DIR" && swift build -c release); then
  ok "Build complete"
else
  fail "Build failed — upgrade aborted (old version still running)"
fi
echo

# ══════════════════════════════════════════════════════
# Step 2: Update hooks → ~/.claude/settings.json
# ══════════════════════════════════════════════════════
printf "${BOLD}[2/4] Updating Claude Code hooks...${NC}\n"

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
mkdir -p "$CLAUDE_DIR"

HOOKS_JSON=$(cat <<HOOKEOF
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$PROJECT_DIR/hooks/notify-stop.sh",
            "async": true
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Read|Bash|Edit|Write|NotebookEdit|AskUserQuestion|ExitPlanMode|mcp__.*",
        "hooks": [
          {
            "type": "command",
            "command": "$PROJECT_DIR/hooks/notify-permission.sh"
          }
        ]
      }
    ]
  },
  "permissions": {
    "allow": [
      "Bash(touch*claudepet-chatter-lock*)",
      "Bash(curl*127.0.0.1:23987*)",
      "Bash(touch*claudepet-chatter-lock*curl*127.0.0.1:23987*)"
    ]
  }
}
HOOKEOF
)

if [ -f "$SETTINGS_FILE" ]; then
  # Detect which ClaudePet components are currently installed.
  # Only re-add components the user hasn't manually removed.
  MERGED=$(jq --arg projdir "$PROJECT_DIR" --argjson new "$HOOKS_JSON" '
    # Save presence flags before removal
    ((.hooks.Stop // []) | any(.hooks[]?; .command | test($projdir; "x"))) as $hadStop
    | ((.hooks.PreToolUse // []) | any(.hooks[]?; .command | test($projdir; "x"))) as $hadPTU
    | ((.permissions.allow // []) | any(test("23987|claudepet-chatter-lock"))) as $hadPerm
    # Remove old ClaudePet entries
    | (.hooks.Stop // []) |= map(
        .hooks |= map(select(.command | test($projdir; "x") | not))
        | select(.hooks | length > 0)
      )
    | (.hooks.PreToolUse // []) |= map(
        .hooks |= map(select(.command | test($projdir; "x") | not))
        | select(.hooks | length > 0)
      )
    | (.permissions.allow // []) |= map(select(test("23987|claudepet-chatter-lock") | not))
    # Re-add only components that were present
    | if $hadStop then .hooks.Stop = ((.hooks.Stop // []) + ($new.hooks.Stop // [])) else . end
    | if $hadPTU then .hooks.PreToolUse = ((.hooks.PreToolUse // []) + ($new.hooks.PreToolUse // [])) else . end
    | if $hadPerm then .permissions.allow = ((.permissions.allow // []) + ($new.permissions.allow // []) | unique) else . end
    # Clean up empty arrays
    | if (.hooks.Stop // []) | length == 0 then del(.hooks.Stop) else . end
    | if (.hooks.PreToolUse // []) | length == 0 then del(.hooks.PreToolUse) else . end
    | if (.hooks // {}) | length == 0 then del(.hooks) else . end
    | if (.permissions.allow // []) | length == 0 then del(.permissions.allow) else . end
    | if (.permissions // {}) | length == 0 then del(.permissions) else . end
  ' "$SETTINGS_FILE")
  echo "$MERGED" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
  ok "Hooks refreshed in $SETTINGS_FILE (respects manual removals)"
else
  echo "$HOOKS_JSON" > "$SETTINGS_FILE"
  ok "Hooks created in $SETTINGS_FILE"
fi
echo

# ══════════════════════════════════════════════════════
# Step 3: Update idle chatter → ~/.claude/CLAUDE.md
# ══════════════════════════════════════════════════════
printf "${BOLD}[3/4] Updating idle chatter config...${NC}\n"

CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

CHATTER_BLOCK=$(cat <<CHATTEREOF

<!-- claudepet-chatter-start -->
## ClaudePet Idle Chatter

At the start of each session, proactively set up an idle chatter schedule using CronCreate:
- Cron minute field: randomly pick 3 different minutes (0-59), comma-separated (e.g. \`7,31,48 * * * *\`). Randomize per session to avoid multiple sessions triggering simultaneously.
- prompt: \`First run touch \$TMPDIR/claudepet-chatter-lock (prevents Stop hook from sending extra "work complete" notifications). Then run curl -s -m 1 http://127.0.0.1:23987/health — if it fails, stop. On success, check the chatterEnabled field in the returned JSON; if false, stop (do not launch subagent). If true, use the Agent tool (model: haiku) to launch a subagent with a prompt that includes: (1) a one-sentence summary of the current conversation and the current time (2) instructions for the subagent to read ${PROJECT_DIR}/Personas/<persona-id>/chatter-prompt.md (persona ID from the health JSON) and follow all rules therein to decide whether to send idle chatter.\`
- After sending chatter (whether cron-triggered or spontaneous), do not report the result to the user — complete silently
- Additionally, you may spontaneously send chatter at appropriate moments during conversation (no need to wait for cron); spontaneous chatter does not require a subagent or the lock file
<!-- claudepet-chatter-end -->
CHATTEREOF
)

if [ -f "$CLAUDE_MD" ] && grep -q "claudepet-chatter-start" "$CLAUDE_MD" 2>/dev/null; then
  # User has chatter enabled — update to latest version
  sed -i '' '/<!-- claudepet-chatter-start -->/,/<!-- claudepet-chatter-end -->/d' "$CLAUDE_MD"
  echo "$CHATTER_BLOCK" >> "$CLAUDE_MD"
  ok "Chatter config updated in $CLAUDE_MD"
else
  ok "Idle chatter not enabled (skipped — enable via status bar menu)"
fi
echo

# ══════════════════════════════════════════════════════
# Step 4: Update shell wrapper
# ══════════════════════════════════════════════════════
printf "${BOLD}[4/4] Checking shell wrapper...${NC}\n"

case "${SHELL:-/bin/zsh}" in
  */zsh)  RC_FILE="$HOME/.zshrc" ;;
  */bash) RC_FILE="$HOME/.bashrc" ;;
  *)      RC_FILE="$HOME/.zshrc" ;;
esac

if [ -f "$RC_FILE" ] && grep -q "$PROJECT_DIR/scripts/launch-pet.sh" "$RC_FILE" 2>/dev/null; then
  ok "Shell wrapper already up to date ($RC_FILE)"
else
  # Remove old ClaudePet wrapper if present (different path)
  if [ -f "$RC_FILE" ] && grep -q "# ClaudePet:" "$RC_FILE" 2>/dev/null; then
    sed -i '' '/# ClaudePet:/,/^}/d' "$RC_FILE"
  fi
  # Add new wrapper
  cat <<WRAPPEREOF >> "$RC_FILE"

# ClaudePet: auto-launch desktop pet when starting Claude Code (singleton)
claude() {
  bash "$PROJECT_DIR/scripts/launch-pet.sh"
  command claude "\$@"
}
WRAPPEREOF
  ok "Shell wrapper updated in $RC_FILE"
fi
echo

# ══════════════════════════════════════════════════════
# Restart ClaudePet
# ══════════════════════════════════════════════════════
printf "${BOLD}Restarting ClaudePet...${NC}\n"
# When launched from menu, ClaudePet terminates itself.
# When launched from terminal, pkill handles it.
# SIGTERM first (allows cleanup), poll for exit, fallback SIGKILL
pkill -f ".build/release/ClaudePet" 2>/dev/null || true
for _ in 1 2 3 4; do
  pgrep -f ".build/release/ClaudePet" >/dev/null 2>&1 || break
  sleep 0.5
done
pkill -9 -f ".build/release/ClaudePet" 2>/dev/null || true
# Wait for old process to fully exit
for _ in 1 2 3 4 5; do
  curl -s -m 1 http://127.0.0.1:23987/health >/dev/null 2>&1 || break
  sleep 1
done
bash "$PROJECT_DIR/scripts/launch-pet.sh"

printf "\n${GREEN}${BOLD}Upgrade complete! ClaudePet v%s is running.${NC}\n\n" "$VERSION"
