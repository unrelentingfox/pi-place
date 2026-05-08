#!/usr/bin/env bash
set -uo pipefail

PIPLACE="$(cd "$(dirname "$0")" && pwd)"
PI_DIR="$PIPLACE/pi"
FAILURES=()

# --- Helpers ---

get_upstream_branch() {
  local dir="$1"
  if [[ -f "$dir/.pprc" ]]; then
    head -1 "$dir/.pprc"
  else
    echo "main"
  fi
}

is_pi_core() { [[ "$(basename "$1")" == "pi" ]]; }

has_build_script() {
  local dir="$1"
  jq -e '.scripts.build' "$dir/package.json" &>/dev/null
}

build_repo() {
  local dir="$1"
  local name
  name="$(basename "$dir")"
  echo "==> $name"
  cd "$dir" || return
  if is_pi_core "$dir"; then
    npm install
    npm run build
    cd "$dir/packages/coding-agent" && npm link
  else
    npm install --ignore-scripts
    if has_build_script "$dir"; then
      npm run build
    fi
  fi
}

for_each_repo() {
  local callback="$1"
  local target="${2:-}"

  if [[ -n "$target" ]]; then
    local dir="$PIPLACE/$target"
    if [[ ! -d "$dir/.git" && ! -f "$dir/.git" ]]; then
      echo "Error: '$target' is not a repo in piplace" >&2
      exit 1
    fi
    if ! "$callback" "$dir"; then
      FAILURES+=("$target")
    fi
  else
    for dir in "$PIPLACE"/*/; do
      dir="${dir%/}"
      if [[ ! -d "$dir/.git" && ! -f "$dir/.git" ]]; then
        continue
      fi
      if ! "$callback" "$dir"; then
        FAILURES+=("$(basename "$dir")")
      fi
    done
  fi
}

report_failures() {
  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo ""
    echo "FAILED: ${FAILURES[*]}"
    exit 1
  fi
}

# --- Commands ---

cmd_install() {
  for_each_repo build_repo "${1:-}"
  report_failures
}

cmd_rebase() {
  local _rebase_one
  _rebase_one() {
    local dir="$1"
    local name branch
    name="$(basename "$dir")"
    echo "==> $name"
    cd "$dir" || return
    if [[ -n "$(git status --porcelain)" ]]; then
      git commit -am "pp: temp commit"
    fi
    git fetch origin
    branch="$(get_upstream_branch "$dir")"
    git rebase "origin/$branch"
  }
  for_each_repo _rebase_one "${1:-}"
  report_failures
}

cmd_reset() {
  local _reset_one
  _reset_one() {
    local dir="$1"
    local name branch
    name="$(basename "$dir")"
    echo "==> $name"
    cd "$dir" || return
    if [[ -n "$(git status --porcelain)" ]]; then
      git stash
    fi
    git fetch origin
    branch="$(get_upstream_branch "$dir")"
    git reset --hard "origin/$branch"
  }
  for_each_repo _reset_one "${1:-}"
  report_failures
}

cmd_add() {
  local url="$1"
  local name
  name="$(basename "$url" .git)"
  cd "$PIPLACE" || exit
  git submodule add "$url" "$name"
  build_repo "$PIPLACE/$name"
  pi install "$PIPLACE/$name"
}

cmd_remove() {
  local name="$1"
  local dir="$PIPLACE/$name"
  if [[ ! -d "$dir" ]]; then
    echo "Error: '$name' not found" >&2
    exit 1
  fi
  read -rp "Remove $name? [y/N] " confirm
  if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    return
  fi
  pi remove "$PIPLACE/$name"
  cd "$PIPLACE" || exit
  git submodule deinit -f "$name"
  git rm -f "$name"
  rm -rf ".git/modules/$name"
}

cmd_status() {
  local _status_one
  _status_one() {
    local dir="$1"
    local name
    name="$(basename "$dir")"
    echo "==> $name"
    cd "$dir" || return
    git status --short
    if git rev-parse --abbrev-ref '@{upstream}' &>/dev/null; then
      git rev-list --left-right --count HEAD...'@{upstream}' | awk '{print "ahead: "$1", behind: "$2}'
    fi
    echo ""
  }
  for_each_repo _status_one
}

cmd_versions() {
  for dir in "$PIPLACE"/*/; do
    dir="${dir%/}"
    if [[ -f "$dir/package.json" ]]; then
      printf "%-25s %s\n" "$(basename "$dir")" "$(jq -r .version "$dir/package.json")"
    fi
  done
}

cmd_test() {
  local _test_one
  _test_one() {
    local dir="$1"
    local name
    name="$(basename "$dir")"
    echo "==> $name"
    cd "$dir" || return
    if jq -e '.scripts.test' package.json &>/dev/null; then
      npm test
    else
      echo "  (no test script)"
    fi
  }
  for_each_repo _test_one "${1:-}"
  report_failures
}

cmd_clean() {
  local _clean_one
  _clean_one() {
    local dir="$1"
    local name
    name="$(basename "$dir")"
    echo "==> $name (cleaning)"
    cd "$dir" || return
    rm -rf node_modules
    build_repo "$dir"
  }
  for_each_repo _clean_one "${1:-}"
  report_failures
}

cmd_link() {
  echo "==> Linking pi"
  cd "$PI_DIR/packages/coding-agent" && npm link
}

usage() {
  cat <<EOF
Usage: ./pp.sh <command> [name]

Commands:
  install [name]    Build and link all (or one) repo
  rebase [name]     Fetch + rebase on upstream (temp commits dirty changes)
  reset [name]      Fetch + hard reset to upstream (stashes dirty changes)
  add <git-url>     Add extension as submodule, build, register
  remove <name>     Unregister, remove submodule
  status            Git status across all repos
  versions          Show package versions
  test [name]       Run tests
  clean [name]      Nuke node_modules, rebuild
  link              Re-link pi globally
EOF
}

# --- Dispatcher ---

cmd="${1:-}"
shift || true

case "$cmd" in
  install)  cmd_install "$@" ;;
  rebase)   cmd_rebase "$@" ;;
  reset)    cmd_reset "$@" ;;
  add)      cmd_add "$@" ;;
  remove)   cmd_remove "$@" ;;
  status)   cmd_status ;;
  versions) cmd_versions ;;
  test)     cmd_test "$@" ;;
  clean)    cmd_clean "$@" ;;
  link)     cmd_link ;;
  *)        usage; [[ -z "$cmd" ]] || exit 1 ;;
esac
