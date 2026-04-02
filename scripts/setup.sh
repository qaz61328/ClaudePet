#!/bin/bash
# ClaudePet Setup Script
# One-command environment setup: build → hooks → CLAUDE.md → shell wrapper
# Usage: bash scripts/setup.sh [--yes]

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

# ── --yes flag ────────────────────────────────────────
AUTO_YES=false
if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
  AUTO_YES=true
fi

# ── Helpers ───────────────────────────────────────────
confirm() {
  if $AUTO_YES; then return 0; fi
  printf "${BOLD}$1 [y/N]${NC} "
  read -r answer
  [[ "$answer" =~ ^[Yy] ]]
}

# Opt-in confirm: --yes does NOT auto-approve (returns 1 = skip)
confirm_opt_in() {
  if $AUTO_YES; then return 1; fi
  printf "${BOLD}$1 [y/N]${NC} "
  read -r answer
  [[ "$answer" =~ ^[Yy] ]]
}

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
skip() { printf "  ${YELLOW}→${NC} %s (already exists, skipped)\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; exit 1; }

# ── Summary tracking ─────────────────────────────────
declare -a SUMMARY=()

# ══════════════════════════════════════════════════════
printf "\n${BOLD}ClaudePet Setup${NC}\n"
printf "Project: %s\n\n" "$PROJECT_DIR"

# ── Prerequisites ─────────────────────────────────────
if ! command -v jq &>/dev/null; then
  fail "jq is required (used by hook scripts). Install it first: brew install jq"
fi

if ! command -v swift &>/dev/null; then
  fail "swift is required (for building). Install Xcode Command Line Tools: xcode-select --install"
fi

# ══════════════════════════════════════════════════════
# Step 1: Build
# ══════════════════════════════════════════════════════
printf "${BOLD}[1/4] Build ClaudePet (release)${NC}\n"
if confirm "  Run swift build -c release?"; then
  (cd "$PROJECT_DIR" && swift build -c release)
  ok "Build complete"
  SUMMARY+=("✓ Built release binary")
else
  SUMMARY+=("→ Skipped build")
fi
echo

# ══════════════════════════════════════════════════════
# Step 2: Claude Code hooks → ~/.claude/settings.json
# ══════════════════════════════════════════════════════
printf "${BOLD}[2/4] Configure Claude Code hooks${NC}\n"

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

if [ -f "$SETTINGS_FILE" ] && grep -q "ClaudePet" "$SETTINGS_FILE" 2>/dev/null; then
  skip "hooks"
  SUMMARY+=("→ Hooks already configured")
else
  if confirm "  Write hooks to ${SETTINGS_FILE}?"; then
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
      # Merge into existing settings (deep merge hooks, dedupe permissions.allow)
      MERGED=$(jq -s '
        .[0] as $existing | .[1] as $new |
        $existing
        | .hooks = (($existing.hooks // {}) * $new.hooks)
        | .permissions.allow = (($existing.permissions.allow // []) + ($new.permissions.allow // []) | unique)
      ' "$SETTINGS_FILE" <(echo "$HOOKS_JSON"))
      echo "$MERGED" > "$SETTINGS_FILE"
    else
      echo "$HOOKS_JSON" > "$SETTINGS_FILE"
    fi
    ok "Hooks written to $SETTINGS_FILE"
    SUMMARY+=("✓ Configured hooks")
  else
    SUMMARY+=("→ Skipped hooks")
  fi
fi
echo

# ══════════════════════════════════════════════════════
# Step 3: Idle chatter schedule → ~/.claude/CLAUDE.md
# ══════════════════════════════════════════════════════
printf "${BOLD}[3/4] Configure idle chatter (CLAUDE.md)${NC}\n"
printf "  ${YELLOW}Note${NC}: This feature sets up a cron job that triggers every ~20 minutes.\n"
printf "  Each trigger uses a small amount of tokens (Haiku sub-agent).\n"

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
  skip "idle chatter"
  SUMMARY+=("→ Idle chatter already configured")
else
  if confirm_opt_in "  Enable idle chatter? (uses tokens, default: no)"; then
    echo "$CHATTER_BLOCK" >> "$CLAUDE_MD"
    ok "Chatter config written to $CLAUDE_MD"
    SUMMARY+=("✓ Configured idle chatter")
  else
    SUMMARY+=("→ Skipped idle chatter (can enable later via status bar menu)")
  fi
fi
echo

# ══════════════════════════════════════════════════════
# Step 4: Shell wrapper → RC file
# ══════════════════════════════════════════════════════
printf "${BOLD}[4/4] Configure shell wrapper${NC}\n"

# Detect shell
case "${SHELL:-/bin/zsh}" in
  */zsh)  RC_FILE="$HOME/.zshrc" ;;
  */bash) RC_FILE="$HOME/.bashrc" ;;
  *)      RC_FILE="$HOME/.zshrc" ;;  # macOS defaults to zsh
esac

WRAPPER_BLOCK=$(cat <<WRAPPEREOF

# ClaudePet: auto-launch desktop pet when starting Claude Code (singleton)
claude() {
  bash "$PROJECT_DIR/scripts/launch-pet.sh"
  command claude "\$@"
}
WRAPPEREOF
)

if [ -f "$RC_FILE" ] && grep -q "launch-pet.sh" "$RC_FILE" 2>/dev/null; then
  skip "shell wrapper ($RC_FILE)"
  SUMMARY+=("→ Shell wrapper already configured")
else
  if confirm "  Add claude() wrapper to ${RC_FILE}?"; then
    echo "$WRAPPER_BLOCK" >> "$RC_FILE"
    ok "Wrapper written to $RC_FILE"
    printf "  ${YELLOW}Note${NC}: Run ${BOLD}source %s${NC} or open a new terminal to apply\n" "$RC_FILE"
    SUMMARY+=("✓ Configured shell wrapper")
  else
    SUMMARY+=("→ Skipped shell wrapper")
  fi
fi
echo

# ══════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════
printf "${BOLD}Setup complete!${NC}\n"
for item in "${SUMMARY[@]}"; do
  printf "  %s\n" "$item"
done
printf "\nRun ${BOLD}claude${NC} to start Claude Code + ClaudePet\n\n"
