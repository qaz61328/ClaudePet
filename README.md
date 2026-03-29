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

ClaudePet runs an HTTP server on `127.0.0.1:23987`. Two Claude Code hooks feed it events: a Stop hook sends notifications when work finishes, and a PreToolUse hook intercepts tool calls that need authorization. The authorization bubble holds the HTTP connection until you click approve or deny, so Claude Code pauses in the meantime.

"Always approve" remembers the tool name for the rest of the session. The memory clears when ClaudePet exits.

For the full HTTP API, animation state machine, and hook integration details, see [CLAUDE.md](CLAUDE.md).

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

ClaudePet ships with a built-in default persona. You can create additional characters with custom dialogue, pixel sprites, and sound effects.

The fastest way: run `/create-persona` inside Claude Code. It walks you through character design and generates everything.

You can also build a persona by hand. Drop a `persona.json` plus optional sprites and sounds into `Personas/<your-id>/`. See [CLAUDE.md](CLAUDE.md) for the full persona architecture.

Switch between installed personas from the status bar menu.

## License

[MIT](LICENSE)
