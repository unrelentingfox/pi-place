# Troubleshooting

## Pi hangs on startup with sandbox enabled

`sandbox-runtime` uses prefix matching, not globs. Paths like `/tmp/*` hang bubblewrap.

Fix: remove `/*` suffixes in `~/.pi/agent/sandbox.json`:
```
"/tmp/*" → "/tmp"
"~/.pi/*" → "~/.pi"
```

## Missing sandbox dependencies (Linux)

```bash
brew install bubblewrap socat ripgrep
# or: sudo apt install bubblewrap socat ripgrep
```

All three (`bwrap`, `socat`, `rg`) must be on PATH.

## Writes blocked despite being in allowWrite

`denyWrite` always wins. Check for conflicting patterns in:
- `~/.pi/agent/sandbox.json` (global)
- `.pi/sandbox.json` (project)

## Disable sandbox

```bash
pi --no-sandbox
```

Or set `"enabled": false` in config.
