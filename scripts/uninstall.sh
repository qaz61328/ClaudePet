#!/bin/bash
# ClaudePet Uninstall Script
# Remove all environment configs and stop the process.
# Usage: bash scripts/uninstall.sh

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

printf "\n${BOLD}ClaudePet Uninstall${NC}\n"
printf "Project: %s\n\n" "$PROJECT_DIR"
printf "${YELLOW}This will remove all ClaudePet hooks, configs, and stop the process.${NC}\n"
printf "${BOLD}Continue? [y/N]${NC} "
read -r answer
if [[ ! "$answer" =~ ^[Yy] ]]; then
  printf "Cancelled.\n"
  exit 0
fi
echo

# ══════════════════════════════════════════════════════
# Step 1: Stop ClaudePet
# ══════════════════════════════════════════════════════
printf "${BOLD}[1/5] Stopping ClaudePet...${NC}\n"
if pkill -f ".build/release/ClaudePet" 2>/dev/null; then
  ok "ClaudePet process stopped"
else
  ok "ClaudePet was not running"
fi
echo

# ══════════════════════════════════════════════════════
# Step 2: Remove hooks from ~/.claude/settings.json
# ══════════════════════════════════════════════════════
printf "${BOLD}[2/5] Removing hooks from settings.json...${NC}\n"

SETTINGS_FILE="$HOME/.claude/settings.json"

if [ -f "$SETTINGS_FILE" ]; then
  if command -v jq &>/dev/null; then
    CLEANED=$(jq --arg projdir "$PROJECT_DIR" '
      # Remove ClaudePet hook entries
      (.hooks.Stop // []) |= map(
        .hooks |= map(select(.command | test($projdir; "x") | not))
        | select(.hooks | length > 0)
      )
      | (.hooks.PreToolUse // []) |= map(
        .hooks |= map(select(.command | test($projdir; "x") | not))
        | select(.hooks | length > 0)
      )
      # Remove empty hook arrays
      | if (.hooks.Stop // []) | length == 0 then del(.hooks.Stop) else . end
      | if (.hooks.PreToolUse // []) | length == 0 then del(.hooks.PreToolUse) else . end
      | if (.hooks // {}) | length == 0 then del(.hooks) else . end
      # Remove ClaudePet permission entry
      | (.permissions.allow // []) |= map(select(test("23987|claudepet-chatter-lock") | not))
      | if (.permissions.allow // []) | length == 0 then del(.permissions.allow) else . end
      | if (.permissions // {}) | length == 0 then del(.permissions) else . end
    ' "$SETTINGS_FILE")
    echo "$CLEANED" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    ok "Hooks removed from $SETTINGS_FILE"
  else
    warn "jq not found — please manually remove ClaudePet entries from $SETTINGS_FILE"
  fi
else
  ok "No settings.json found (nothing to remove)"
fi
echo

# ══════════════════════════════════════════════════════
# Step 3: Remove chatter section from ~/.claude/CLAUDE.md
# ══════════════════════════════════════════════════════
printf "${BOLD}[3/5] Removing idle chatter config from CLAUDE.md...${NC}\n"

CLAUDE_MD="$HOME/.claude/CLAUDE.md"

if [ -f "$CLAUDE_MD" ] && grep -q "claudepet-chatter-start" "$CLAUDE_MD" 2>/dev/null; then
  sed -i '' '/<!-- claudepet-chatter-start -->/,/<!-- claudepet-chatter-end -->/d' "$CLAUDE_MD"
  ok "Chatter config removed from $CLAUDE_MD"
else
  ok "No chatter config found (nothing to remove)"
fi
echo

# ══════════════════════════════════════════════════════
# Step 4: Remove shell wrapper from RC file
# ══════════════════════════════════════════════════════
printf "${BOLD}[4/5] Removing shell wrapper...${NC}\n"

case "${SHELL:-/bin/zsh}" in
  */zsh)  RC_FILE="$HOME/.zshrc" ;;
  */bash) RC_FILE="$HOME/.bashrc" ;;
  *)      RC_FILE="$HOME/.zshrc" ;;
esac

if [ -f "$RC_FILE" ] && grep -q "# ClaudePet:" "$RC_FILE" 2>/dev/null; then
  # Remove from "# ClaudePet:" comment to closing "}" of the claude() function
  sed -i '' '/# ClaudePet:/,/^}/d' "$RC_FILE"
  ok "Shell wrapper removed from $RC_FILE"
else
  ok "No shell wrapper found in $RC_FILE (nothing to remove)"
fi
echo

# ══════════════════════════════════════════════════════
# Step 5: Clean up temp files
# ══════════════════════════════════════════════════════
printf "${BOLD}[5/5] Cleaning up temp files...${NC}\n"
rm -f /tmp/claudepet-session-allow-* /tmp/claudepet-chatter-lock
ok "Temp files cleaned"
echo

# ══════════════════════════════════════════════════════
printf "${GREEN}${BOLD}Uninstall complete!${NC}\n"
printf "  To re-install later:  ${BOLD}bash scripts/setup.sh${NC}\n"
printf "  To delete the repo:   ${BOLD}rm -rf %s${NC}\n\n" "$PROJECT_DIR"
