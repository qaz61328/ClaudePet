#!/bin/bash
# ClaudePet TTS — Edge TTS provider (Microsoft neural voices, free)
# Requires: pip install edge-tts
# Input:  TTS_TEXT, TTS_VOICE_EDGE (default: en-US-AriaNeural)
# Output: path to generated MP3 file on stdout

set -euo pipefail

[ -z "${TTS_TEXT:-}" ] && exit 1
command -v edge-tts >/dev/null 2>&1 || exit 1

VOICE="${TTS_VOICE_EDGE:-${TTS_VOICE:-en-US-AriaNeural}}"
TMPFILE="$(mktemp "${TMPDIR:-/tmp}/claudepet-tts-XXXXXX")"
mv "$TMPFILE" "${TMPFILE}.mp3"
TMPFILE="${TMPFILE}.mp3"

# Generate audio (stderr silenced, timeout handled by Swift caller)
if ! edge-tts --text "$TTS_TEXT" --voice "$VOICE" --write-media "$TMPFILE" 2>/dev/null; then
  rm -f "$TMPFILE"
  exit 1
fi

# Verify file was actually created and is non-empty
if [ ! -s "$TMPFILE" ]; then
  rm -f "$TMPFILE"
  exit 1
fi

echo "$TMPFILE"
