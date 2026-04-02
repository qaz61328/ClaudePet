# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| latest release | Yes |
| older releases | No |

Only the latest release receives security fixes. Update to the latest version before reporting.

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Instead, use GitHub's private vulnerability reporting:

1. Go to the [Security Advisories](https://github.com/qaz61328/ClaudePet/security/advisories) page
2. Click **"Report a vulnerability"**
3. Fill in the details

You should receive an initial response within a week. If the vulnerability is confirmed, a fix will be released as soon as possible and you will be credited (unless you prefer otherwise).

## Security Scope

ClaudePet runs locally on macOS. The main security-relevant areas are:

- **HTTP server** (`127.0.0.1:23987`): Bound to localhost only. POST endpoints require an auth token (`X-ClaudePet-Token` header) and validate the Host header to prevent DNS rebinding.
- **Auth token**: UUID generated per launch, stored in `$TMPDIR/claudepet-token` with mode `0600`. Used by hook scripts to authenticate requests.
- **Temp files**: All temp files (`claudepet-token`, `claudepet-session-allow-*`, `claudepet-passthrough-auth`, `claudepet-chatter-lock`) are stored in `$TMPDIR` (macOS per-user directory, not world-accessible).
- **Hook scripts**: Shell scripts that pass data to the HTTP server. All JSON payloads are assembled with `jq -n --arg` to prevent injection.

## Out of Scope

- Attacks that require local root access (ClaudePet runs as the current user)
- Denial of service against the local HTTP server
- Issues in Claude Code itself (report those to [Anthropic](https://github.com/anthropics/claude-code/issues))
