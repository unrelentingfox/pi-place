# AGENTS.md

## Repository

This is a git repo managing pi (the terminal AI coding agent) and its extensions as submodules. Managed by `pp.sh`.

## Submodules

| Directory | Purpose |
|---|---|
| `pi/` | Pi core (coding agent) |
| `pi-provider-kiro/` | Kiro LLM provider |
| `mi-sandbox/` | OS-level sandboxing (network, filesystem, bash policy) |
| `pi-vim/` | Vim keybindings |
| `pi-nvim/` | Neovim integration |
| `pi-web-access/` | Web search and content extraction |

## Build System

Not a Brazil workspace. Uses npm directly.

- Pi core: `npm install` + `npm run build` + `npm link` (from `packages/coding-agent`)
- Extensions: `npm install --ignore-scripts` + `npm run build`

Use `./pp.sh install [name]` to build everything or a single repo.

## Key Files

- `pp.sh` — management script (install, rebase, reset, add, remove, status)
- `mi-sandbox/index.ts` — sandbox extension source (single-file extension)
- `~/.pi/agent/settings.json` — registered extensions list
- `~/dotfiles/pi/sandbox.json` — sandbox policy config (network, filesystem, bash)

## Conventions

- Extensions are registered via `pi install <path>`
- Default upstream branch is `main` (override with `.pprc` in submodule)
- `pp.sh` must pass shellcheck and shfmt
- Commit messages follow Conventional Commits

## Sandbox Policy

The `mi-sandbox` extension enforces:
- **Network**: domain allowlist for outbound requests
- **Filesystem**: read/write path restrictions
- **Bash**: command allow/deny patterns with configurable default policy

Config lives in `~/dotfiles/pi/sandbox.json` (global) and `.sandbox.json` (per-project).

## Documentation

After making changes to submodules, pp.sh, or sandbox config, update:
- `README.md` — if commands or usage changed
- `AGENTS.md` — if submodules, key files, or conventions changed
