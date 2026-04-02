# Setup Guide

## Prerequisites

- **macOS 13+** (Ventura or later)
- **Swift 5.9+** (install with `xcode-select --install` if you don't have Xcode Command Line Tools)
- **jq** (used by the authorization hook script; install with `brew install jq`)

## Quick Start

```bash
bash scripts/setup.sh
```

The script walks through four steps, asking for confirmation at each one. Pass `--yes` to skip the prompts (idle chatter is opt-in and skipped in `--yes` mode):

```bash
bash scripts/setup.sh --yes
```

What it does:

1. Builds the release binary (`swift build -c release`)
2. Writes Claude Code hook configuration to `~/.claude/settings.json`
3. Asks whether to enable idle chatter (opt-in, default: no). If yes, appends the chatter config block to `~/.claude/CLAUDE.md`
4. Adds a `claude()` shell wrapper to your RC file (`~/.zshrc` or `~/.bashrc`)

After setup, run `claude` as usual. ClaudePet starts in the background before Claude Code launches.

## Manual Setup

If you prefer to configure things yourself, follow these four steps.

### 1. Build

```bash
cd /path/to/ClaudePet
swift build -c release
```

The binary ends up at `.build/release/ClaudePet`. No external dependencies needed.

### 2. Claude Code Hooks

Add hooks to `~/.claude/settings.json`. Replace `/path/to/ClaudePet` with your actual project path:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/ClaudePet/hooks/notify-stop.sh",
            "async": true
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Read|Bash|Edit|Write|NotebookEdit|AskUserQuestion|ExitPlanMode|mcp__.*",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/ClaudePet/hooks/notify-permission.sh"
          }
        ]
      }
    ]
  },
  "permissions": {
    "allow": [
      "Bash(touch*claudepet-chatter-lock*)",
      "Bash(curl*127.0.0.1:23987*)",
      "Bash(touch*claudepet-chatter-lock*curl*127.0.0.1:23987*)"
    ]
  }
}
```

The `permissions.allow` entries let ClaudePet-related Bash commands (chatter lock file, curl to the local server) run without triggering an authorization prompt.

If you already have a `settings.json`, merge the `hooks` and `permissions` sections into your existing file.

### 3. Idle Chatter (Opt-in)

Idle chatter is disabled by default. To enable it, append this block to `~/.claude/CLAUDE.md` (or toggle it on from the status bar menu later):

```markdown
<!-- claudepet-chatter-start -->
## ClaudePet Idle Chatter

At the start of each session, set up a chatter schedule using CronCreate:
- Cron minute field: pick 3 random minutes (0-59), comma-separated (e.g. `7,31,48 * * * *`). Randomize per session to avoid multiple sessions firing at the same time.
- Prompt: `First run touch $TMPDIR/claudepet-chatter-lock (prevents the Stop hook from sending an extra "work complete" notification). Then run curl -s -m 1 http://127.0.0.1:23987/health. If it fails, stop. If it succeeds, check the chatterEnabled field in the response JSON. If false, stop (do not launch subagent). If true, launch a subagent with the Agent tool (model: haiku). The subagent prompt should include: (1) a one-line summary of the current conversation and the current time (2) instructions to read /path/to/ClaudePet/Personas/<persona-id>/chatter-prompt.md (get persona ID from the health JSON) and follow all rules within to decide whether to send chatter.`
- After sending chatter (whether cron or spontaneous), do not report the result. Complete silently.
- You can also send chatter spontaneously when the timing feels right (no cron, no lock file needed).
<!-- claudepet-chatter-end -->
```

Replace `/path/to/ClaudePet` with your actual project path. The `<!-- claudepet-chatter-start/end -->` markers are required — the status bar menu toggle and upgrade script use them to safely add/remove the block.

### 4. Shell Wrapper (Auto-Launch)

Add this to your `~/.zshrc` (or `~/.bashrc`):

```bash
claude() {
  bash /path/to/ClaudePet/scripts/launch-pet.sh
  command claude "$@"
}
```

`launch-pet.sh` checks the `/health` endpoint first. If ClaudePet is already running, it skips the launch. If the binary doesn't exist, it builds it.

After editing your RC file, run `source ~/.zshrc` or open a new terminal.

## Update

Click **Check for Updates** in the status bar menu. ClaudePet checks the latest [GitHub Release](https://github.com/qaz61328/ClaudePet/releases) and handles the upgrade automatically: pull the latest code, rebuild, update all configs, and restart.

To update manually:

```bash
git pull origin main
bash scripts/upgrade.sh
```

The upgrade script:
1. Rebuilds the release binary
2. Updates Claude Code hooks in `~/.claude/settings.json` (only refreshes hooks that are still present; respects manual removals)
3. Updates the idle chatter block in `~/.claude/CLAUDE.md` if enabled (skips if chatter was never enabled)
4. Updates the shell wrapper if the project path changed
5. Restarts ClaudePet

## Uninstall

```bash
bash scripts/uninstall.sh
```

The script asks for confirmation, then:
1. Stops the ClaudePet process
2. Removes ClaudePet hooks and permissions from `~/.claude/settings.json`
3. Removes the idle chatter block from `~/.claude/CLAUDE.md`
4. Removes the `claude()` shell wrapper from your RC file
5. Cleans up temp files (`$TMPDIR/claudepet-*`)

Your other settings in `settings.json` and `CLAUDE.md` are preserved. The script does not delete the repo — do that yourself if you want:

```bash
rm -rf /path/to/ClaudePet
```

## Custom Personas

The fastest way to create a persona: run `/create-persona` inside Claude Code. It asks you about the character and generates dialogue, sprites, and sounds.

To build one by hand, create a directory under `Personas/<your-id>/` with:

- `persona.json` (dialogue definitions, see `.claude/commands/references/persona-schema.md` for the schema)
- 20 sprite PNGs: `idle_1.png` through `idle_4.png`, `bow_1.png` through `bow_4.png`, `alert_1.png` through `alert_4.png`, `happy_1.png` through `happy_4.png`, `working_1.png` through `working_4.png` (64x64 pixels, transparent background)
- Sound files (optional, supports .aif/.wav/.mp3): `startup.aif` (launch), `notify.aif` (notifications), `authorize.aif` (authorization prompts)
- `chatter-prompt.md` (defines chatter behavior for this persona, optional)

All of these except `persona.json` are optional. Missing sprites fall back to the built-in set, and missing sounds fall back to silence.

Switch personas from the status bar menu. The selection persists across restarts. Use "Reload Personas" at the bottom of the menu to pick up newly added personas without restarting.

## Keyboard Shortcuts

ClaudePet registers system-wide keyboard shortcuts that work regardless of which app is focused. No Accessibility permission required.

### Default Bindings

| Action | Shortcut | Description |
|--------|----------|-------------|
| Toggle Pet | `⌃⌥P` | Show/hide the pet |
| Allow (Auth) | `⌃⌥Y` | Approve the pending authorization request |
| Always Allow (Auth) | `⌃⌥A` | Always allow for the rest of the session |
| Deny (Auth) | `⌃⌥N` | Deny the pending authorization request |

The three authorization shortcuts only take effect when an authorization bubble is active. At all other times they do nothing.

### Customizing

Open the status bar menu and click **Keyboard Shortcuts...**. A preferences window appears with one row per action. Click a row to enter recording mode, then press a modifier+key combination to set the new shortcut.

- At least one modifier key (⌃, ⌥, ⇧, or ⌘) is required
- Press **Esc** to cancel recording
- Press **Delete** to clear the binding
- Duplicate bindings are detected and rejected with a warning

Click **Restore Defaults** to reset all shortcuts to the defaults above.

Custom bindings persist in UserDefaults across restarts.

## Token Usage Note

The idle chatter feature uses a CronCreate-triggered subagent running on the haiku model. Each chatter check consumes a small number of tokens: the subagent reads the chatter prompt file, evaluates whether to speak, and if so, sends a short POST request.

If you want to minimize token usage, disable idle chatter from the status bar menu ("Idle Chatter" toggle). The toggle takes effect immediately; no restart needed.

## Troubleshooting

**ClaudePet doesn't start**

Check that the binary exists:
```bash
ls .build/release/ClaudePet
```
If it's missing, rebuild: `swift build -c release`

Check that port 23987 is free:
```bash
lsof -i :23987
```

**Authorization bubbles don't appear**

Verify the hooks are configured:
```bash
cat ~/.claude/settings.json | jq '.hooks'
```

Make sure `jq` is installed:
```bash
which jq
```

The hook scripts need `jq` to parse Claude Code's JSON input. Without it, the PreToolUse hook exits silently and Claude Code falls through to its default permission flow.

**ClaudePet is running but Claude Code doesn't trigger it**

Test the server directly:
```bash
curl http://127.0.0.1:23987/health
```

You should get back `{"status":"ok","persona":"default",...}`. If the request fails, ClaudePet isn't running or something else is using port 23987.

**Idle chatter isn't firing**

1. Check that "Idle Chatter" is enabled in the status bar menu
2. Verify the `~/.claude/CLAUDE.md` chatter block exists
3. Test the endpoint: `curl -X POST http://127.0.0.1:23987/chatter -H "Content-Type: application/json" -d '{"message":"test"}'`

**Character is stuck in working animation**

The working state tracks active Claude Code sessions. If a session crashes without sending `/working active=false`, the state can get stuck. Sessions auto-expire after 3 minutes, so wait it out, or restart ClaudePet from the status bar menu.
