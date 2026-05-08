# pi-place

Pi and its extensions, installed from source as git submodules. Managed by `pp.sh`.

## Usage

```bash
cd ~/pi-place
./pp.sh <command> [name]
```

## Commands

| Command | Description |
|---|---|
| `install [name]` | Build and link all (or one) repo |
| `rebase [name]` | Fetch + rebase on upstream (temp commits dirty changes) |
| `reset [name]` | Fetch + hard reset to upstream (stashes dirty changes) |
| `add <git-url>` | Add extension as submodule, build, register with pi |
| `remove <name>` | Unregister, remove submodule |
| `status` | Git status across all repos |
| `versions` | Show package versions |
| `test [name]` | Run tests |
| `clean [name]` | Nuke node_modules, rebuild |
| `link` | Re-link pi globally |

## Adding an extension

```bash
./pp.sh add git@github.com:samfoy/pi-memory.git
```

## Branch configuration

Each submodule defaults to rebasing/resetting against `main`. Override by creating a `.pprc` file in the submodule directory containing the branch name.

## Contributing to pp.sh

After editing `pp.sh`, run:

```bash
shellcheck pp.sh
shfmt -d pp.sh    # check formatting (-w to apply)
```
