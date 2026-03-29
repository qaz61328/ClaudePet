#!/bin/bash
# ClaudePet Singleton Launcher
# Check if already running, only start if not

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BINARY="$PROJECT_DIR/.build/release/ClaudePet"
HEALTH_URL="http://127.0.0.1:23987/health"

# Already running → skip
if curl -s -m 1 "$HEALTH_URL" >/dev/null 2>&1; then
  exit 0
fi

# Binary not found → try to build
if [ ! -f "$BINARY" ]; then
  echo "[ClaudePet] Binary not found, building..."
  (cd "$PROJECT_DIR" && swift build -c release 2>/dev/null)
fi

# Launch in background, detached from terminal
nohup "$BINARY" >/dev/null 2>&1 &

# Wait for startup to complete (up to 3 seconds)
for i in 1 2 3; do
  sleep 1
  if curl -s -m 1 "$HEALTH_URL" >/dev/null 2>&1; then
    exit 0
  fi
done

echo "[ClaudePet] Warning: failed to start" >&2
