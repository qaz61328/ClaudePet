# ClaudePet

A macOS desktop pet that replaces Claude Code's terminal permission prompts with an interactive pixel-art character.

ClaudePet sits on your desktop and intercepts Claude Code's notification and authorization events through hooks. When Claude Code finishes work, the character pops a speech bubble. When Claude Code needs permission to run a command or edit a file, the character shows an authorization bubble with approve/deny buttons. You click the bubble instead of typing in the terminal.

## Features

- Pixel-art character with idle, bow, alert, and happy animations (4 frames each)
- Speech bubbles for "work complete", "needs your input", and "plan ready" notifications
- Authorization flow with three options: approve once, always approve this tool, or deny
- Idle chatter: the character mumbles to itself throughout the day, driven by a cron-scheduled subagent
- Persona system: swap characters with different dialogue, sprites, and sound effects
- Status bar menu for toggling visibility, switching personas, and controlling idle chatter
- Sound effects on notifications and authorization requests (per-persona, with fallback)
- Auto-launch via a shell wrapper that starts ClaudePet before every `claude` invocation

## How it works

ClaudePet runs an HTTP server on `127.0.0.1:23987`. Two Claude Code hooks feed it events:

```
Claude Code
    |
    +-- Stop hook ------------ POST /notify ------> speech bubble ("work complete")
    |
    +-- PreToolUse hook
          +-- AskUserQuestion - POST /notify ------> speech bubble ("needs your input")
          +-- ExitPlanMode ---- POST /notify ------> speech bubble ("plan ready")
          |
          +-- Bash/Edit/Write - POST /authorize ---> authorization bubble (approve / always / deny)
                                                     holds the HTTP connection until you click
                                                     Claude Code pauses in the meantime

CronCreate (scheduled / spontaneous)
    +-- POST /chatter -------> idle chatter mumble (no sound, discarded if a bubble is showing)
```

"Always approve" remembers the tool name for the rest of the session. The memory clears when ClaudePet exits.

## Quick start

Requirements: macOS 13+, Swift 5.9+ (Xcode Command Line Tools), `jq`

```bash
git clone https://github.com/qaz61328/ClaudePet.git
cd ClaudePet
bash scripts/setup.sh
```

The setup script builds the binary, configures Claude Code hooks, sets up idle chatter scheduling, and adds a shell wrapper so ClaudePet launches with every `claude` invocation.

For step-by-step instructions or manual configuration, see [SETUP.md](SETUP.md).

## Personas

ClaudePet ships with a built-in butler persona. You can create additional characters with custom dialogue, pixel sprites, and sound effects.

The fastest way: run `/create-persona` inside Claude Code. It walks you through character design and generates everything.

You can also build a persona by hand. Drop a `persona.json` plus optional sprites and sounds into `Personas/<your-id>/`. See [CLAUDE.md](CLAUDE.md) for the full persona architecture.

Switch between installed personas from the status bar menu.

## Project structure

```
Sources/ClaudePet/
  main.swift              # app entry, persona loading, startup greeting
  PetWindow.swift         # transparent borderless window, position persistence
  PetView.swift           # character rendering, animation state machine, bubble management
  SpeechBubble.swift      # notification bubble + authorization bubble
  SoundPlayer.swift       # per-persona sound loading with fallback
  PetServer.swift         # HTTP server (NWListener + CFHTTPMessage)
  DialogueBank.swift      # Persona protocol, ButlerPersona fallback, DialogueBank facade
  PersonaLoader.swift     # JSON model, DataDrivenPersona, AuthorizeFormatter, PersonaDirectory
  StatusBarMenu.swift     # status bar menu + persona switching submenu
  TerminalActivator.swift # click-to-switch-back-to-terminal (iTerm2 / Terminal.app)
  Resources/butler/       # built-in butler persona sprites + persona.json + sounds

hooks/
  notify-stop.sh          # Claude Code Stop hook
  notify-permission.sh    # Claude Code PreToolUse hook

scripts/
  setup.sh                # one-command environment setup
  launch-pet.sh           # singleton launcher (skips if already running)
  generate_sprites.py     # sprite generation template (Pillow)

Personas/                 # persona directory (scanned at startup, git-ignored)
```

For architecture details, HTTP API reference, and the animation state machine diagram, see [CLAUDE.md](CLAUDE.md).

## License

[MIT](LICENSE)
