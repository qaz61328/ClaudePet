# FAQ

## Authorization

### How do I disable authorization prompts?

Remove the `PreToolUse` hook from `~/.claude/settings.json`. ClaudePet will still show notifications but will no longer intercept tool authorization.

### I can't see the details of what's being authorized

Enable "Passthrough Auth" from the status bar menu. In this mode, ClaudePet only sends a notification that authorization is needed, without intercepting the authorization content. The actual approval happens in Claude Code's native terminal dialog, which shows full diffs and command details.

## Idle Chatter

### Why does an Agent suddenly run on its own?

That's the idle chatter feature. ClaudePet uses a small amount of tokens to generate context-aware dialogue via a subagent. You can toggle it off from the status bar menu under "Idle Chatter." Note that the agent activity will always be visible in the terminal — this cannot be hidden.

### What is `.claude/scheduled_tasks.lock`?

This file is not created by ClaudePet. It's part of Claude Code's own scheduling infrastructure. Whenever any session uses `CronCreate` to set up a cron job, Claude Code places this lock file under `.claude/` in the project directory.

Since the idle chatter instruction in `~/.claude/CLAUDE.md` tells Claude to create a cron job at the start of every session, this file will appear in every project you work on.

You can either add it to your `.gitignore_global` to hide it, or if you don't want idle chatter at all, remove all chatter-related instructions from `~/.claude/CLAUDE.md`.

### Why does idle chatter sometimes not start?

The idle chatter cron job is configured through instructions in `~/.claude/CLAUDE.md`. Sometimes Claude skips it because:

1. The instruction sits in the middle of the file and gets diluted by other instructions
2. Claude focuses on the user's first message at the start of a session
3. Phrasing like "at the start of each session" can be treated as background info and ignored

The most effective fix: move the cron setup instruction to the very top of your `~/.claude/CLAUDE.md` with stronger, more directive wording in its own section.

## Persona & Customization

### The generated persona doesn't look the way I want

Try providing more detailed appearance descriptions when running `/create-persona`. Specifics like colors, outfit style, accessories, and hair style help produce better results. For example: "blue hoodie, round glasses, orange cat ears" works much better than "a cute character."

### Can I use my own custom sprites?

Yes. Place your sprite PNGs in the persona's `Personas/<id>/` directory with the correct naming convention (e.g., `idle_1.png`, `idle_2.png`, `bow_1.png`, etc.). Each animation state needs at least 2 frames, but you can add more than 4. Just make sure the filenames follow the `<state>_<number>.png` pattern.

### Can I use custom sound effects?

Yes. Each persona can have its own sound effects. Place sound files in the persona's `Personas/<id>/` directory. Startup sounds: `startup.aif`, `startup.wav`, `startup.mp3`. Notification sounds: `notify.aif`, `notify.wav`, `notify.mp3`. Authorization sounds: `authorize.aif`, `authorize.wav`, `authorize.mp3`. If no custom sound is found, it falls back to the built-in default.

## Known Issues

### Claude Code's Dream mode triggers authorization prompts

This is a known issue. Dream mode runs tool calls in the background, which triggers the PreToolUse hook the same way normal operations do. There is no workaround yet.

### Auto Edit Mode still triggers authorization bubbles or notifications

This is a known issue. When Claude Code runs in Auto Edit Mode, it skips its own permission prompts but still fires PreToolUse hooks. The hook cannot distinguish between normal mode and Auto Edit Mode, so ClaudePet shows authorization bubbles (or notification bubbles in Passthrough Auth mode) as usual. There is no workaround yet.

### Grep and Glob tools don't go through ClaudePet authorization

This is a known issue. The PreToolUse hook only intercepts destructive or interactive tools (Bash, Edit, Write, etc.). Grep and Glob are read-only search tools, so their authorization falls back to Claude Code's built-in terminal UI instead of ClaudePet's bubble.
