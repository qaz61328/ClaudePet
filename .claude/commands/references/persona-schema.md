# ClaudePet Persona Schema Reference

## Persona Directory Structure

Each persona is a folder under `Personas/<id>/` at the project root:

```
Personas/
  <persona-id>/
    persona.json          # Dialogue data (required)
    idle_1.png            # Sprite: idle frame 1 (baseline position)
    idle_2.png            # Sprite: idle frame 2 (slight rise)
    idle_3.png            # Sprite: idle frame 3 (highest point)
    idle_4.png            # Sprite: idle frame 4 (descending back)
    bow_1.png             # Sprite: bow frame 1 (slight tilt)
    bow_2.png             # Sprite: bow frame 2 (light bow)
    bow_3.png             # Sprite: bow frame 3 (deep bow)
    bow_4.png             # Sprite: bow frame 4 (rising back)
    alert_1.png           # Sprite: alert frame 1 (surprised lift)
    alert_2.png           # Sprite: alert frame 2 (higher + flicker)
    alert_3.png           # Sprite: alert frame 3 (drop back + wider stance)
    alert_4.png           # Sprite: alert frame 4 (bounce up again)
    happy_1.png           # Sprite: happy frame 1 (crouch/wind-up)
    happy_2.png           # Sprite: happy frame 2 (jump apex)
    happy_3.png           # Sprite: happy frame 3 (descending)
    happy_4.png           # Sprite: happy frame 4 (landing)
    working_1.png         # Sprite: working frame 1 (leaning forward, typing)
    working_2.png         # Sprite: working frame 2 (slight dip rhythm)
    working_3.png         # Sprite: working frame 3 (head lift)
    working_4.png         # Sprite: working frame 4 (lean forward again)
    startup.aif           # Sound: startup entrance sound (optional)
    notify.aif            # Sound: notification chime (optional)
    authorize.aif         # Sound: authorization prompt sound (optional)
    chatter-prompt.md     # Idle chatter prompt (optional, read by CronCreate)
    generate_sprites.py   # Script to generate the above PNGs (optional)
```

## persona.json Full Schema

```json
{
  "id": "Unique ID used for directory name and persistence (lowercase English + hyphens)",
  "displayName": "Name displayed in the menu",

  "greeting": {
    "morning":   ["Morning (6:00-11:59) greeting lines, 6-8 entries"],
    "afternoon": ["Afternoon (12:00-17:59) greeting lines"],
    "evening":   ["Evening (18:00-23:59) greeting lines"],
    "lateNight": ["Late night (0:00-5:59) greeting lines"]
  },

  "taskComplete": {
    "generic":     ["Lines when Claude Code finishes work (without project name)"],
    "withProject": ["Version with project name, use {project} as placeholder"]
  },

  "authorize": {
    "openers": ["Opening lines at the top of the authorization bubble, 4-6 entries"],
    "fileToolLabels": {
      "Edit":         { "pathIcon": "pencil-emoji", "actionLabel": "action-description" },
      "Write":        { "pathIcon": "pencil-emoji", "actionLabel": "action-description" },
      "NotebookEdit": { "pathIcon": "notebook-emoji", "actionLabel": "action-description" }
    },
    "buttonLabels": {
      "approve": "✓ Allow button text",
      "approveSession": "✓ Always Allow button text",
      "deny": "✗ Deny button text"
    }
  },

  "authorized":       ["Response after user presses Allow, 6-8 entries"],
  "denied":           ["Response after user presses Deny, 6-8 entries"],
  "clicked":          ["Response when user clicks the persona, 10-14 entries (more is better)"],
  "switchToTerminal": ["Lines when switching to the terminal, 6-8 entries"],

  "needsAttention": {
    "generic":     ["Notification when Claude Code needs user input (without project name)"],
    "withProject": ["Version with project name, use {project} as placeholder"]
  },

  "planReady": {
    "generic":     ["Notification when Plan Mode plan is ready (without project name)"],
    "withProject": ["Version with project name, use {project} as placeholder"]
  },
  "checkTerminalAuth": {
    "generic":     ["Notification in 'Authorize in Terminal' mode — alert user that authorization is needed (optional, has fallback)"],
    "withProject": ["Version with project name, use {project} as placeholder"]
  }
}
```

## Dialogue Writing Guidelines

### Character Consistency
- All lines within each method should reflect the same personality
- Self-reference and user address should be consistent
- Tone intensity should be uniform (don't mix formal and casual within the same pool)

### Context for Each Method
| Method | Trigger | Dialogue Direction |
|--------|---------|-------------------|
| greeting | App launch or menu "Say something" | Greet, show concern for the user |
| taskComplete | Claude Code finishes work | Report completion, invite review |
| authorize.openers | Authorization needed to run a tool | Request permission |
| authorize.buttonLabels | Allow / Always Allow / Deny buttons | Static labels (not arrays). Include ✓/✗ prefix. Optional; defaults to English if omitted |
| authorized | User grants permission | Thank, confirm execution |
| denied | User denies permission | Accept gracefully, no pressure |
| clicked | User clicks the persona | Interactive, playful, everyday feel |
| switchToTerminal | Guiding user back to the terminal | Lead the way, point to terminal |
| needsAttention | Claude Code needs user decision | Alert, request attention |
| planReady | Plan Mode plan is prepared | Report the plan, request approval |
| checkTerminalAuth | "Authorize in Terminal" mode, tool needs permission | Alert user that authorization is waiting for their decision |

### Avoiding Repetition
- Avoid identical sentence structures within each pool
- Mix long and short lines
- Don't start every line with the same word

## Sound Effect Specifications

- **Formats**: .aif / .wav / .mp3 (the system tries loading in this order)
- **Duration**: Recommended 0.5-2 seconds
- **File naming**: Must follow these exact names
  - `startup.aif` — Plays when the persona appears (app launch greeting)
  - `notify.aif` — Plays when a notification bubble appears (task complete, needs attention, plan ready)
  - `authorize.aif` — Plays when an authorization bubble appears (requesting tool permission)
- **Optional**: Sound files are optional. Personas without custom sounds automatically use built-in defaults
- **Fallback order**: Persona directory -> built-in default -> silence

## Idle Chatter Prompt (chatter-prompt.md)

The `chatter-prompt.md` file in the persona directory is read by Claude Code's CronCreate to periodically generate in-character idle chatter.

**File Structure:**
- Title: `# Idle Chatter Prompt — <Persona Name>`
- Persona summary: One sentence describing the persona's relationship with the user
- Voice paragraph: How the persona addresses the user, self-reference, speech style
- Rules paragraph: Character limit (15 chars max), skip when busy, no repeats, chatter directions, complete silently after sending
- Send method: Fixed curl POST command template (endpoint: `/chatter`)

**Optional**: Personas without this file will work normally — they just won't have scheduled idle chatter.

Example reference: `Personas/default/chatter-prompt.md`

## Sprite Specifications

- **Size**: 64 x 64 pixels
- **Format**: PNG, RGBA (transparent background)
- **Style**: Pixel art — the app displays at 96pt with interpolation disabled
- **Naming**: Must follow the `<state>_<frame>.png` format strictly

### Per-State Animation Descriptions (4 frames each)
| State | Frames | Description |
|-------|--------|-------------|
| idle | 1->2->3->4 | Breathing cycle. Baseline -> slight rise -> highest -> return (1-2px vertical float) |
| bow | 1->2->3->4 | Bow cycle. Slight tilt -> light bow -> deep bow -> rise back |
| alert | 1->2->3->4 | Alert jitter. Surprised expression + raised hands + alternating exclamation mark position for flicker effect |
| happy | 1->2->3->4 | Jump arc. Crouch wind-up -> apex -> descending -> landing, with waving and star effects |
| working | 1->2->3->4 | Working/typing. Lean forward -> slight dip rhythm -> head lift -> lean forward again, hands typing in front |

## Sprite Generation Python Script

Each persona's `generate_sprites.py` is based on the project's `scripts/generate_sprites.py` template.
Main customization points:
- **Palette**: `BODY`, `BODY_DARK`, `BODY_LIGHT` and other color constants
- **Accessories**: Bowtie can be replaced with other items (ears, hat, wings, etc.)
- **Expression details**: Eye shape, mouth style
- **Effects**: Star colors, exclamation mark style

The script's `main()` output directory should be set to the script's own folder:
```python
out = os.path.dirname(os.path.abspath(__file__))
```

## Built-in Default Example

A complete persona JSON example can be found in the project at:
`Sources/ClaudePet/Resources/default/persona.json`
