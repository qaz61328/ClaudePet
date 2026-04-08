# ClaudePet Developer Reference

macOS native desktop pet application with multi-persona pixel-art characters. Intercepts Claude Code's notification and authorization flow, replacing terminal permission dialogs with interactive desktop bubbles.

## Tech Stack

- **Language**: Swift 5.9+
- **Framework**: AppKit (pure AppKit, no SwiftUI)
- **Build**: Swift Package Manager (executable target)
- **HTTP Server**: NWListener (Network framework) + CFHTTPMessage (CFNetwork)
- **Minimum version**: macOS 13+
- **Zero external dependencies** (system frameworks only)

## Architecture

```
Main.swift                PetWindow.swift           PetView.swift
SpeechBubble.swift        SoundPlayer.swift         TTSPlayer.swift
PetServer.swift
GlobalHotKeyManager.swift ShortcutRecorderView.swift DialogueBank.swift
PersonaLoader.swift       TerminalActivator.swift   StatusBarMenu.swift
Resources/
```

### Animation State Machine

```
idle/working --(click)--> bow -> talking -> restingState*
             --(/notify type=ask)--> talking -> restingState* (AskUserQuestion notification)
             --(/notify type=plan)--> talking -> restingState* (Plan Mode plan ready)
             --(/chatter)--> talking -> restingState* (idle chatter, TTS if enabled, 3.5s; discarded if auth/notify showing)
             --(/authorize)--> alert + AuthBubble
               +--(allow / ⌃⌥Y)--> happy -> restingState*
               +--(deny / ⌃⌥N)--> restingState*
               +--(60s no action)--> alert (bubble dismissed, character stays in alert animation)
               |    +--(click character)--> re-show AuthBubble
               |    +--(⌃⌥Y / ⌃⌥A / ⌃⌥N)--> same as button click (hotkey works even after bubble dismiss)
               +--(client disconnect)--> restingState* (auto cleanup)

idle --(/working active=true)--> working
working --(/working active=false, no other sessions)--> idle

* restingState = working if active sessions exist, otherwise idle
```

### HTTP Endpoints

All POST endpoints require auth token (`X-ClaudePet-Token` header) and Host header validation. GET `/health` is unauthenticated. Request bodies are limited to 64KB.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Returns `{"status":"ok","version":"<ver>","persona":"<id>","activeSessions":<n>,"chatterEnabled":<bool>,"ttsEnabled":<bool>,"terminalAuthMode":<bool>}` |
| POST | `/notify` | Notification. Returns 200 immediately. `type` field: `"ask"`, `"plan"` |
| POST | `/authorize` | Authorization request. Holds connection until user clicks. 60-second timeout. |
| POST | `/chatter` | Idle chatter (TTS if enabled). Body: `{"message":"..."}`. Silently discarded if auth/notify showing. |
| POST | `/working` | Session work state. Body: `{"session":"<uuid>","active":true/false,"context":"<brief work description>"}`. 3-minute auto-expiry. |

### Security

- **Auth token**: UUID per launch → `$TMPDIR/claudepet-token` (mode 0600). All POST requests validated.
- **DNS rebinding protection**: Host header validated against `127.0.0.1:23987` / `localhost:23987`.
- **$TMPDIR for temp files**: macOS per-user directory (not world-accessible) instead of `/tmp`.
- **Safe JSON**: All responses use `JSONEncoder`. All hook curl payloads use `jq -n --arg`. No string interpolation.

### Claude Code Hook Integration

Integrates with Claude Code's [hook system](https://docs.anthropic.com/en/docs/claude-code/hooks).

**Stop hook** (`notify-stop.sh`):
1. POST `/working` (active=false) to end session's working state
2. POST `/notify` to show "work complete" bubble

**Working-state hook** (`notify-working.sh`, async, matches all tools):
- POST `/working` (active=true) on every tool call to keep working animation in sync

**Permission hook** (`notify-permission.sh`, sync, matches auth-eligible tools):
1. POST `/working` (active=true, context=tool description) with work context update
2. `AskUserQuestion` → POST `/notify` (type=ask); `ExitPlanMode` → POST `/notify` (type=plan)
3. **Authorize in Terminal** mode → exit 0 silently (no pet bubble, Claude Code handles auth natively)
4. Check session-allow list (tools "always allowed" pass through). File: `$TMPDIR/claudepet-session-allow-<md5(CWD)>`
5. Check `permissions.allow` from Claude Code settings (global/project/local) — matching patterns exit 0 silently
6. **Pet auth mode** (default) → POST `/authorize` for interactive bubble

Two auth modes switchable via status bar menu. Persisted in UserDefaults, synced to `$TMPDIR/claudepet-passthrough-auth` file flag.

### Idle Chatter

- **Trigger**: ClaudePet detects idle state (all sessions ended) → starts timer (5 min ± random jitter) → runs external script
- **Generation**: Pluggable shell script (`scripts/generate-chatter.sh`) calls LLM API with persona prompt + work context → returns one line of text
- **Script env vars**: `CHATTER_PROMPT_PATH`, `CHATTER_CONTEXT`, `CHATTER_PERSONA`, `CHATTER_TIME`, `CHATTER_RECENT`, `CLAUDEPET_TOKEN`
- **Script lookup**: `Personas/<id>/generate-chatter.sh` → `scripts/generate-chatter.sh` → skip silently
- **Providers**: Auto-detect (Anthropic Direct / AWS Bedrock / Claude Code CLI). Provider-specific scripts in `scripts/chatter-*.sh`
- **External POST**: `/chatter` endpoint still available for external callers
- **Priority**: `authorize > notify > working > chatter > idle` — chatter always yields
- **Opt-in**: Disabled by default. Enable via status bar menu toggle (`UserDefaults` key: `chatterEnabled`)

### TTS (Text-to-Speech)

- **Scope**: Chatter bubbles only (notify/authorize/greeting do not trigger TTS)
- **Architecture**: Pluggable shell script (`scripts/tts.sh`) generates audio file → Swift plays via NSSound
- **Script env vars**: `TTS_TEXT`, `TTS_PERSONA`, `TTS_VOICE_EDGE`, `TTS_VOICE_SAY`, `TTS_PROVIDER`
- **Script lookup**: `Personas/<id>/tts.sh` → `scripts/tts.sh`
- **Providers**: Auto-detect (Edge TTS → macOS say). Provider-specific scripts in `scripts/tts-*.sh`
- **Voice config**: Optional `tts` field in `persona.json` with `edgeTTS` and `say` voice names
- **Cancellation**: New speak() call cancels previous playback + cleans up temp audio file
- **Opt-in**: Disabled by default. Enable via Settings > TTS (`UserDefaults` key: `ttsEnabled`)

### Persona System

- Persona data: `Personas/<id>/` — `persona.json` + 20 sprite PNGs (5 states × 4 frames, optional) + sounds (optional) + `chatter-prompt.md` (optional)
- JSON schema: `.claude/commands/references/persona-schema.md`
- Switching: status bar submenu, persisted in UserDefaults (`selectedPersonaID`)
- Sprites/sounds: 3-tier fallback (persona dir → Bundle.module → placeholder/silence)
- Create: `/create-persona` or build by hand

## Setup

```bash
bash scripts/setup.sh       # interactive setup
bash scripts/setup.sh --yes # skip confirmation (idle chatter skipped in --yes mode)
```

## Development

```bash
swift build              # debug build
swift build -c release   # release build
swift run                # launch (debug)
```
