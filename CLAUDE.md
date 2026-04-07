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
SpeechBubble.swift        SoundPlayer.swift         PetServer.swift
GlobalHotKeyManager.swift ShortcutRecorderView.swift DialogueBank.swift
PersonaLoader.swift       TerminalActivator.swift   StatusBarMenu.swift
Resources/
```

### Animation State Machine

```
idle/working --(click)--> bow -> talking -> restingState*
             --(/notify type=ask)--> talking -> restingState* (AskUserQuestion notification)
             --(/notify type=plan)--> talking -> restingState* (Plan Mode plan ready)
             --(/chatter)--> talking -> restingState* (idle chatter, no sound, 3.5s; discarded if auth/notify showing)
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
| GET | `/health` | Returns `{"status":"ok","version":"<ver>","persona":"<id>","activeSessions":<n>,"chatterEnabled":<bool>,"terminalAuthMode":<bool>}` |
| POST | `/notify` | Notification. Returns 200 immediately. `type` field: `"ask"`, `"plan"` |
| POST | `/authorize` | Authorization request. Holds connection until user clicks. 60-second timeout. |
| POST | `/chatter` | Idle chatter (no sound). Body: `{"message":"..."}`. Silently discarded if auth/notify showing. |
| POST | `/working` | Session work state. Body: `{"session":"<uuid>","active":true/false}`. 3-minute auto-expiry. |

### Security

- **Auth token**: UUID per launch → `$TMPDIR/claudepet-token` (mode 0600). All POST requests validated.
- **DNS rebinding protection**: Host header validated against `127.0.0.1:23987` / `localhost:23987`.
- **$TMPDIR for temp files**: macOS per-user directory (not world-accessible) instead of `/tmp`.
- **Safe JSON**: All responses use `JSONEncoder`. All hook curl payloads use `jq -n --arg`. No string interpolation.

### Claude Code Hook Integration

Integrates with Claude Code's [hook system](https://docs.anthropic.com/en/docs/claude-code/hooks).

**Stop hook** (`notify-stop.sh`):
1. POST `/working` (active=false) to end session's working state
2. Check `$TMPDIR/claudepet-chatter-lock` — if exists, delete and skip notification
3. POST `/notify` to show "work complete" bubble

**PreToolUse hook** (`notify-permission.sh`):
1. POST `/working` (active=true) fire-and-forget
2. `AskUserQuestion` → POST `/notify` (type=ask); `ExitPlanMode` → POST `/notify` (type=plan)
3. **Authorize in Terminal** mode → exit 0 silently (no pet bubble, Claude Code handles auth natively)
4. Check session-allow list (tools "always allowed" pass through). File: `$TMPDIR/claudepet-session-allow-<md5(CWD)>`
5. Check `permissions.allow` from Claude Code settings (global/project/local) — matching patterns exit 0 silently
6. **Pet auth mode** (default) → POST `/authorize` for interactive bubble

Two auth modes switchable via status bar menu. Persisted in UserDefaults, synced to `$TMPDIR/claudepet-passthrough-auth` file flag.

### Idle Chatter

- **Scheduled**: CronCreate → `touch $TMPDIR/claudepet-chatter-lock` → subagent reads `Personas/<id>/chatter-prompt.md`
- **Spontaneous**: POST `/chatter` during conversation
- **Priority**: `authorize > notify > working > chatter > idle` — chatter always yields
- **Opt-in**: Disabled by default. Enable via `setup.sh` or status bar menu toggle (`UserDefaults` key: `chatterEnabled`)
- **CLAUDE.md config block**: `<!-- claudepet-chatter-start/end -->` markers, managed by toggle

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
