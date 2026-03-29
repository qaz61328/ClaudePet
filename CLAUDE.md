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
Main.swift              # App entry, NSApplication setup, persona loading, startup greeting
PetWindow.swift         # Transparent borderless window + position persistence (UserDefaults)
PetView.swift           # Character rendering + animation state machine + bubble management + per-persona sprite loading
SpeechBubble.swift      # Notification bubble (SpeechBubbleView) + authorization bubble (AuthBubbleView)
SoundPlayer.swift       # Sound playback (NSSound) + per-persona sound loading + fallback
PetServer.swift         # HTTP Server (NWListener + CFHTTPMessage)
DialogueBank.swift      # Persona protocol + DefaultPersona (fallback) + DialogueBank facade
PersonaLoader.swift     # PersonaData (JSON model) + DataDrivenPersona + AuthorizeFormatter + PersonaDirectory
TerminalActivator.swift # Click-to-switch-to-terminal (detects iTerm2/Terminal.app + AppleScript tab switching)
StatusBarMenu.swift     # Status bar menu + persona switching submenu
Resources/              # Built-in pixel sprites PNG + persona.json (default/ subdirectory)
```

### Core Components

- **Transparent borderless window** (`ClickThroughWindow`): `.borderless`, `.floating`, transparent background, draggable
- **HTTP Server** (port 23987): bound to 127.0.0.1, `@MainActor` + `queue: .main` for Swift 6 concurrency safety
- **Authorization async hold**: `/authorize` uses `CheckedContinuation` to hold the connection until the user clicks a button
- **Status bar icon** (NSStatusBar): show/hide, say something, persona switching, quit
- **No Dock icon**: `NSApp.setActivationPolicy(.accessory)`

### Animation State Machine

```
idle/working --(click)--> bow -> talking -> restingState*
             --(/notify)--> talking -> restingState*
             --(/notify type=ask)--> talking -> restingState* (AskUserQuestion notification)
             --(/notify type=plan)--> talking -> restingState* (Plan Mode plan ready)
             --(/chatter)--> talking -> restingState* (idle chatter, no sound, 3.5s; discarded if auth/notify showing)
             --(/authorize)--> alert + AuthBubble
               +--(approve)--> happy -> restingState*
               +--(deny)--> restingState*
               +--(60s no action)--> alert (bubble dismissed, character stays in alert animation)
               |    +--(click character)--> re-show AuthBubble
               +--(client disconnect)--> restingState* (auto cleanup)

idle --(/working active=true)--> working
working --(/working active=false, no other sessions)--> idle

* restingState = working if active sessions exist, otherwise idle
```

### HTTP Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check. Returns `{"status":"ok","persona":"<id>","activeSessions":<n>,"chatterEnabled":<bool>}` |
| POST | `/notify` | Notification (work complete, needs attention, etc.). Returns 200 immediately. Supports `type` field (`"ask"` = needs user decision, `"plan"` = Plan Mode plan ready) |
| POST | `/authorize` | Authorization request. Holds the connection until the user clicks a button. 60-second timeout. |
| POST | `/chatter` | Idle chatter (no sound). Returns 200 immediately. Body: `{"message":"mumble text"}`. Silently discarded if an auth/notify bubble is showing. |
| POST | `/working` | Session work state tracking. Returns 200 immediately. Body: `{"session":"<uuid>","active":true/false}`. Multi-session reference counting, 3-minute auto-expiry. |

### Claude Code Hook Integration

ClaudePet integrates with Claude Code's [hook system](https://docs.anthropic.com/en/docs/claude-code/hooks):

**Stop hook** (`notify-stop.sh`):
1. POST `/working` (active=false) to end the session's working state
2. Check for `/tmp/claudepet-chatter-lock`. If it exists, delete it and skip the notification (cron-triggered chatter sessions don't need a "work complete" bubble).
3. POST `/notify` to show a "work complete" speech bubble

**PreToolUse hook** (`notify-permission.sh`):
1. Fire-and-forget POST `/working` (active=true) to mark the session as active
2. `AskUserQuestion`: POST `/notify` (type=ask) for a non-blocking notification bubble
3. `ExitPlanMode`: POST `/notify` (type=plan) for a non-blocking notification bubble
4. Other tools (Bash/Edit/Write/NotebookEdit): check session-allow list first, then POST `/authorize` for an authorization bubble (approve / always approve / deny)

Hook output uses the `hookSpecificOutput` structure:
```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}
```

### Session Authorization Memory

- "Always approve" writes the tool name to `/tmp/claudepet-session-allow`
- The hook script checks this file first. Tools already approved skip the authorization bubble.
- ClaudePet clears this file on exit.

### Idle Chatter

The character occasionally mumbles to itself, adding life to the desktop.

**Trigger methods:**
- **Scheduled**: Claude Code's CronCreate fires a cron job. The job first runs `touch /tmp/claudepet-chatter-lock` (prevents the Stop hook from sending an extra "work complete" notification), then launches a subagent that reads `Personas/<id>/chatter-prompt.md` to decide what to say. The subagent approach avoids bloating the main conversation context.
- **Spontaneous**: Claude can POST `/chatter` at any point during a conversation when the timing feels right. No cron, no lock file needed.

**Dialogue generation modes** (defined in `chatter-prompt.md`): situational reactions, encouragement, idle rambling, time awareness, self-deprecation, humming, health reminders, weather/seasonal comments. Eight modes total, selected by context.

**Priority**: `authorize > notify > working > chatter > idle`. Chatter always yields. If an auth or notify bubble is showing, the chatter request gets silently dropped.

**Toggle**: Status bar menu "Idle Chatter" toggle (`UserDefaults` key: `chatterEnabled`, on by default).

**Auto-scheduling**: The global `~/.claude/CLAUDE.md` instructs Claude to set up a chatter cron at the start of every session (project-independent).

### Persona System (Multi-Character)

The persona system uses a dual architecture: JSON data-driven with Swift fallback.

**Data layer (JSON):**
- Persona data lives in `Personas/<id>/` under the project root
- Each persona contains `persona.json` (dialogue) + 20 sprite PNGs (5 states × 4 frames, optional) + sound files (optional) + `chatter-prompt.md` (chatter prompt, optional)
- On first launch, ClaudePet exports the built-in default persona to `Personas/default/`
- JSON schema defined in `.claude/commands/references/persona-schema.md`

**Code layer (Swift):**
- `Persona` protocol: defines 9 dialogue methods
- `DataDrivenPersona`: loads from JSON, implements the Persona protocol
- `DefaultPersona`: hardcoded default character (fallback if JSON is corrupted)
- `AuthorizeFormatter`: shared assembly logic for authorization text (simplifyCommand, etc.)
- `PersonaDirectory`: scans the `Personas/` directory and loads all personas
- `DialogueBank`: unified entry facade. Callers don't need to know which persona is active.

**Persona switching:**
- Status bar menu "Personas" submenu: lists all installed personas
- `DialogueBank.switchPersona(to:)` switches and posts a `personaDidChange` notification
- PetView observes this notification and reloads sprites
- Selection persists in `UserDefaults` (key: `selectedPersonaID`)
- "Reload Personas" at the bottom of the menu hot-reloads newly added persona directories

**Sprite loading (3-tier fallback):**
1. `Personas/<id>/` custom sprites
2. `Bundle.module` built-in sprites
3. Code-generated placeholder sprites

**Sound loading fallback (same pattern):**
1. `Personas/<id>/notify.aif` custom sound
2. `Bundle.module` built-in sound (default)
3. Silence (no sound found, no playback)
- Supports .aif / .wav / .mp3, tried in order
- `SoundPlayer` observes `.personaDidChange` and reloads sounds on persona switch

**Adding new personas:**
- Run `/create-persona` in Claude Code for interactive persona generation
- Or create `Personas/<new-id>/` manually with persona.json + sprites + sounds

### Singleton Launch

- `scripts/launch-pet.sh`: checks `/health`, only launches if not already running
- `claude()` wrapper in `~/.zshrc` auto-starts ClaudePet

## Setup

```bash
bash scripts/setup.sh       # interactive setup (step-by-step confirmation)
bash scripts/setup.sh --yes # skip confirmation, run everything
```

Handles: release build, Claude Code hooks, idle chatter scheduling in `~/.claude/CLAUDE.md`, shell wrapper.

## Development

```bash
swift build              # debug build
swift build -c release   # release build
swift run                # launch (debug)
```

### Sprite Resources

- 20 PNGs (idle/bow/alert/happy/working, 4 frames each), stored in `Sources/ClaudePet/Resources/`
- `persona.json` in `Resources/default/` subdirectory (built-in default dialogue)
- Sound files (`notify.mp3`, `authorize.mp3`) in `Resources/default/` subdirectory
- `Package.swift` configured with `.copy("Resources/default")`
- Missing PNGs fall back to code-generated placeholder sprites
- Missing sounds fall back to silence

### Built-in Default Persona

- Friendly, casual tone
- Dialogue varies by time of day (morning/afternoon/evening/late night)
- Greets on startup

Other personas can be created via `/create-persona` or built by hand.
