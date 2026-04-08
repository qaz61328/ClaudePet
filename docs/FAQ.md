# FAQ

## Authorization

### How do I turn off permission notifications?

Remove the `PreToolUse` hook from `~/.claude/settings.json`. ClaudePet will still show "work complete" notifications but stop intercepting tool authorizations.

### I can't see what's being authorized

Enable "Authorize in Terminal" in the status bar menu. ClaudePet will notify you that authorization is needed, then hand the approval back to Claude Code's built-in terminal dialog. You get the full diff and command details there.

### "Always allow" doesn't persist across sessions

"Always allow" applies to the current session only. Claude Code's tool authorization is session-scoped and provides no cross-session persistence.

To allow specific tools permanently, add the authorization rules to `.claude/settings.json` by hand.

### Plan Mode asks for write permission on first use

When Claude enters Plan Mode for the first time in a conversation, it writes a plan file to `.claude/plans/`. Claude Code's permission system prompts for approval before allowing that write.

Add this rule to the `permissions.allow` array in `~/.claude/settings.json`:

```json
"Write(*/.claude/plans/*)"
```

Plan files will be auto-allowed after this change.

## Idle Chatter

### How does idle chatter work?

ClaudePet detects when all Claude Code sessions have ended. After a delay (about 5 minutes with random jitter), it runs an external shell script that calls an LLM to generate a short persona-flavored line. The script auto-detects your provider: Anthropic API, AWS Bedrock, or Claude Code CLI (`claude -p --bare`).

This happens entirely within the ClaudePet process — no Claude Code subagents, no cron jobs, no terminal output.

### Chatter isn't showing up

1. Enable "Idle Chatter" in the status bar menu (disabled by default)
2. Make sure an LLM provider is available (`ANTHROPIC_API_KEY`, AWS CLI configured, or `claude` CLI installed)
3. Chatter only fires after all Claude Code sessions end and a ~5-minute delay passes
4. Check that `scripts/generate-chatter.sh` is executable (`chmod +x scripts/generate-chatter.sh`)

## Characters and Customization

### The generated persona doesn't match what I wanted

Give `/create-persona` more specific visual descriptions. Colors, clothing style, accessories, hairstyle. "Blue body, round glasses, orange cat ears" produces better results than "a cute character".

### Can I use my own sprites?

Yes. Drop your sprite PNGs into the persona's `Personas/<id>/` directory. Name them `<state>_<number>.png` (e.g. `idle_1.png`, `idle_2.png`, `bow_1.png`). Each animation state needs at least 2 frames. You can add more than 4.

### Can I use custom sounds?

Yes. Each persona can have its own sounds. Place sound files in `Personas/<id>/`. Startup sound: `startup.mp3`. Notification sound: `notify.mp3`. Authorization sound: `authorize.mp3`. Supported formats: AIF, WAV, MP3. Missing custom sounds fall back to the built-in defaults.

### Can the character walk around the screen?

A helper that wanders across your display on its own sounds **distracting**. No plans for this feature.

## Known Issues (patches welcome)

### Claude Code's Dream feature triggers authorization notifications

Dream mode fires PreToolUse hooks when running tool calls in the background, same as normal operation. No fix available.

### Auto Edit Mode still shows authorization or notification bubbles

Claude Code skips its own authorization prompt in Auto Edit Mode, but PreToolUse hooks fire regardless. The hook cannot distinguish between normal mode and Auto Edit Mode, so ClaudePet shows authorization bubbles (or notification bubbles in "Authorize in Terminal" mode) as usual. No fix available.

### Grep and Glob bypass ClaudePet authorization

The PreToolUse hook intercepts destructive or interactive tools (Bash, Edit, Write, etc.) only. Grep and Glob are read-only search tools. Their authorization falls back to Claude Code's built-in terminal UI and skips ClaudePet's authorization bubble.

### Editing `.claude/` files bypasses ClaudePet authorization

When Claude Code edits files inside the `.claude/` directory (skills, settings, etc.), it uses a built-in settings-protection mechanism instead of the normal PreToolUse hook flow. The terminal shows a special dialog with an "allow Claude to edit its own settings for this session" option. ClaudePet's authorization bubble does not appear for these edits. No fix available — this is a Claude Code internal behavior.
