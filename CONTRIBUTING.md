# Contributing to ClaudePet

Thanks for your interest in ClaudePet! This project is built by me and Claude Code together. Contributions of all kinds are welcome — bug reports, feature ideas, code, docs, and persona designs.

## Getting Started

### Prerequisites

- macOS 13+
- Swift 5.9+ (Xcode Command Line Tools)
- `jq` (for hook scripts)
- Claude Code (for hooks integration and testing)

### Development Setup

```bash
git clone https://github.com/qaz61328/ClaudePet.git
cd ClaudePet
swift build          # debug build
swift run            # launch in debug mode
```

For a full setup with hooks and shell integration:

```bash
bash scripts/setup.sh
```

### Project Structure

The codebase is pure Swift with AppKit — no SwiftUI, no external dependencies. See [CLAUDE.md](CLAUDE.md) for the full architecture reference including the animation state machine, HTTP endpoints, and hook integration.

## Reporting Bugs

Open an [issue](https://github.com/qaz61328/ClaudePet/issues/new?template=bug_report.yml) with:

- What happened vs. what you expected
- Steps to reproduce
- macOS version and ClaudePet version (shown in the status bar menu)
- Relevant logs if available

## Suggesting Features

Open an [issue](https://github.com/qaz61328/ClaudePet/issues/new?template=feature_request.yml) describing the feature and why it would be useful.

## Submitting Pull Requests

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Verify: `swift build -c release` succeeds with no errors
4. Test manually — launch the app, trigger the flows you changed
5. Open a PR against `main`

### Code Style

- Follow existing patterns in the codebase
- Zero external dependencies — use system frameworks only (AppKit, Network, CFNetwork, Carbon)
- All HTTP handler code must be `@MainActor`-safe
- Update comments when you change the code they describe
- Keep commits focused — one logical change per commit

### Personas

A community persona gallery is planned for the future. For now, personas are created locally for personal use — run `/create-persona` in Claude Code or build one by hand in `Personas/<id>/`.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
