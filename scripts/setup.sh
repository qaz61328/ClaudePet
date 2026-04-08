#!/bin/bash
# ClaudePet Setup Script
# One-command environment setup: build → hooks → chatter → TTS → shell wrapper
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
printf "${BOLD}[1/5] Build ClaudePet (release)${NC}\n"
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
printf "${BOLD}[2/5] Configure Claude Code hooks${NC}\n"

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
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "$PROJECT_DIR/hooks/notify-working.sh",
            "async": true
          }
        ]
      },
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
  }
}
HOOKEOF
)

    if [ -f "$SETTINGS_FILE" ]; then
      # Merge into existing settings (deep merge hooks)
      MERGED=$(jq -s '
        .[0] as $existing | .[1] as $new |
        $existing
        | .hooks = (($existing.hooks // {}) * $new.hooks)
      ' "$SETTINGS_FILE" <(echo "$HOOKS_JSON"))
      echo "$MERGED" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
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
# Step 3: Idle chatter (LLM provider for script-based generation)
# ══════════════════════════════════════════════════════
printf "${BOLD}[3/5] Configure idle chatter${NC}\n"
printf "  Idle chatter generates short persona-flavored lines via LLM.\n"
printf "  ClaudePet detects idle time and runs a script to call the provider.\n"
printf "  Providers: Anthropic API, AWS Bedrock, or Claude Code CLI (claude -p --bare).\n"
printf "  Enable/disable via the status bar menu toggle.\n"

CHATTER_SCRIPT="$PROJECT_DIR/scripts/generate-chatter.sh"
if [ -x "$CHATTER_SCRIPT" ]; then
  skip "chatter script (generate-chatter.sh already executable)"
  SUMMARY+=("→ Chatter script ready")
else
  chmod +x "$CHATTER_SCRIPT" 2>/dev/null && ok "Made generate-chatter.sh executable" || true
  SUMMARY+=("✓ Chatter script configured")
fi

# Check available providers (display only; runtime detection in generate-chatter.sh)
PROVIDER_FOUND=false
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  ok "Detected Anthropic API key"
  PROVIDER_FOUND=true
elif command -v aws &>/dev/null && { [ -n "${AWS_ACCESS_KEY_ID:-}" ] || [ -f "$HOME/.aws/credentials" ] || [ -f "$HOME/.aws/config" ]; }; then
  ok "Detected AWS credentials (Bedrock)"
  PROVIDER_FOUND=true
elif command -v claude &>/dev/null; then
  ok "Detected Claude Code CLI (claude -p --bare fallback)"
  PROVIDER_FOUND=true
fi

if ! $PROVIDER_FOUND; then
  printf "  ${YELLOW}Note${NC}: No LLM provider detected. Chatter will be silent until one is configured.\n"
  printf "  Supported: ANTHROPIC_API_KEY, AWS Bedrock (aws CLI), Claude Code CLI\n"
  SUMMARY+=("→ No LLM provider detected (chatter will be silent)")
fi
echo

# ══════════════════════════════════════════════════════
# Step 4: TTS (text-to-speech for chatter)
# ══════════════════════════════════════════════════════
printf "${BOLD}[4/5] Configure TTS (text-to-speech)${NC}\n"
printf "  TTS reads chatter text aloud using neural voices.\n"
printf "  Providers: Edge TTS (neural, requires Python) or macOS say (built-in, offline).\n"
printf "  Enable/disable via Settings > TTS.\n"

TTS_SCRIPT="$PROJECT_DIR/scripts/tts.sh"
if [ -x "$TTS_SCRIPT" ]; then
  skip "TTS scripts (already executable)"
else
  chmod +x "$TTS_SCRIPT" "$PROJECT_DIR/scripts/tts-edge.sh" "$PROJECT_DIR/scripts/tts-say.sh" 2>/dev/null && ok "Made TTS scripts executable" || true
fi

if command -v edge-tts &>/dev/null; then
  ok "Detected edge-tts (neural voices)"
  SUMMARY+=("✓ TTS: edge-tts available")
elif command -v pipx &>/dev/null; then
  if confirm_opt_in "  Install edge-tts for neural-quality voices? (pipx install edge-tts)"; then
    if pipx install edge-tts 2>/dev/null; then
      ok "edge-tts installed"
      SUMMARY+=("✓ TTS: edge-tts installed")
    else
      printf "  ${YELLOW}Note${NC}: pipx install failed. macOS say will be used as fallback.\n"
      SUMMARY+=("→ TTS: edge-tts install failed, macOS say fallback")
    fi
  else
    ok "Using macOS say (built-in, offline)"
    SUMMARY+=("→ TTS: macOS say (built-in)")
  fi
else
  printf "  To install edge-tts later: brew install pipx && pipx install edge-tts\n"
  ok "Using macOS say (built-in)"
  SUMMARY+=("→ TTS: macOS say (built-in)")
fi
echo

# ══════════════════════════════════════════════════════
# Step 5: Shell wrapper → RC file
# ══════════════════════════════════════════════════════
printf "${BOLD}[5/5] Configure shell wrapper${NC}\n"

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
