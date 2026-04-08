#!/bin/bash
# ClaudePet TTS — Auto-detect provider
# Generates audio file from text via Edge TTS or macOS say.
# Input:  TTS_TEXT, TTS_VOICE_EDGE, TTS_VOICE_SAY, TTS_PROVIDER (override)
# Output: path to generated audio file on stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Provider override: TTS_PROVIDER=edge-tts|say
if [ -n "${TTS_PROVIDER:-}" ]; then
  case "$TTS_PROVIDER" in
    edge-tts) exec "$SCRIPT_DIR/tts-edge.sh" ;;
    say)      exec "$SCRIPT_DIR/tts-say.sh" ;;
    *) exit 1 ;;
  esac
fi

# Auto-detect: prefer edge-tts (better quality), fallback to macOS say
if command -v edge-tts >/dev/null 2>&1; then
  exec "$SCRIPT_DIR/tts-edge.sh"
fi

# macOS say is always available
exec "$SCRIPT_DIR/tts-say.sh"
