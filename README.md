# ClaudePet

Your desktop buddy for Claude Code. Intercepts permissions, pops notifications, mumbles to itself.

<p align="center">
  <img src="docs/media/idle.gif" width="96" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.3.7-blue" />
  <img src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" />
</p>

A pixel-art desktop pet that lives next to your terminal.
It replaces Claude Code's permission prompts with clickable speech bubbles,
notifies you when work is done, and occasionally talks to itself when bored.
Create your own character with custom dialogue, sprites, and sounds.

## Features

<p align="center">
  <img src="docs/media/features.png" height="120" />
</p>

- Pixel-art character with idle, bow, alert, and happy animations
- Speech bubbles for work complete, needs input, and plan ready events
- Allow once, always allow, or deny — replaces terminal permission prompts
- Idle chatter when bored — ClaudePet runs an external script to generate persona-flavored lines
- Persona system with custom dialogue, sprites, and sound effects
- Status bar menu for visibility, persona switching, and chatter control
- Auto-launch with every `claude` invocation

## How it works

<p align="center">
  <img src="docs/media/how-it-works.png" height="120" />
</p>

ClaudePet runs an HTTP server on `127.0.0.1:23987`. Two Claude Code hooks feed it events: a Stop hook sends notifications when work finishes, and a PreToolUse hook intercepts tool calls that need authorization. The authorization bubble holds the HTTP connection until you click allow or deny, so Claude Code pauses in the meantime.

"Always Allow" remembers the tool name for the rest of the session. The memory clears when ClaudePet exits.

For the full HTTP API, animation state machine, and hook integration details, see [CLAUDE.md](CLAUDE.md).

## Quick start

<p align="center">
  <img src="docs/media/quick-start.png" height="210" />
</p>

Requirements: macOS 13+, Swift 5.9+ (Xcode Command Line Tools), `jq`

```bash
git clone https://github.com/qaz61328/ClaudePet.git
cd ClaudePet
bash scripts/setup.sh
```

The setup script builds the binary, configures Claude Code hooks, checks for LLM providers (idle chatter), and adds a shell wrapper so ClaudePet launches with every `claude` invocation.

For step-by-step instructions or manual configuration, see [SETUP.md](docs/SETUP.md) | [繁體中文](docs/SETUP_zh-TW.md).

## Update

<p align="center">
  <img src="docs/media/update.png" height="120" />
</p>

Click **Check for Updates** in the status bar menu. ClaudePet checks the latest GitHub Release and walks you through the upgrade automatically.

To update manually:

```bash
git pull origin main
bash scripts/upgrade.sh
```

The upgrade script rebuilds the binary, updates Claude Code hooks and configs, and restarts ClaudePet.

## Uninstall

<p align="center">
  <img src="docs/media/uninstall.png" height="120" />
</p>

```bash
bash scripts/uninstall.sh
```

This removes all ClaudePet environment configs: Claude Code hooks, the shell wrapper, and temp files. It does not delete the repo itself.

## Personas

Every character is fully customizable — dialogue, pixel sprites, and sound effects. Build your own or use the built-in default.

<p align="center">
  <img src="docs/media/cat.png" width="60" />
  <img src="docs/media/milk.png" width="60" />
  <img src="docs/media/claude.png" width="60" />
  <img src="docs/media/pom.png" width="60" />
  <img src="docs/media/sun.png" width="60" />
  <img src="docs/media/eel.png" width="60" />
</p>

The fastest way: run `/create-persona` inside Claude Code. It walks you through character design and generates everything.

You can also build a persona by hand. Drop a `persona.json` plus optional sprites and sounds into `Personas/<your-id>/`. See [CLAUDE.md](CLAUDE.md) for the full persona architecture.

Switch between installed personas from the status bar menu.

## FAQ

<p align="center">
  <img src="docs/media/faq.png" height="120" />
</p>

See [FAQ.md](docs/FAQ.md) | [繁體中文](docs/FAQ_zh-TW.md)

## Contributing

This project is built by me and Claude Code together. If you run into any issues, feel free to modify the code yourself or submit a PR. See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

[MIT](LICENSE)
