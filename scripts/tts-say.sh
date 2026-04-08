#!/bin/bash
# ClaudePet TTS — macOS say provider (built-in, offline)
# Input:  TTS_TEXT, TTS_VOICE_SAY (default: Samantha)
# Output: path to generated AIFF file on stdout

set -euo pipefail

[ -z "${TTS_TEXT:-}" ] && exit 1

VOICE="${TTS_VOICE_SAY:-${TTS_VOICE:-Samantha}}"
TMPFILE="$(mktemp "${TMPDIR:-/tmp}/claudepet-tts-XXXXXX")"
mv "$TMPFILE" "${TMPFILE}.aiff"
TMPFILE="${TMPFILE}.aiff"

if ! say -v "$VOICE" -o "$TMPFILE" "$TTS_TEXT" 2>/dev/null; then
  rm -f "$TMPFILE"
  exit 1
fi

if [ ! -s "$TMPFILE" ]; then
  rm -f "$TMPFILE"
  exit 1
fi

echo "$TMPFILE"
