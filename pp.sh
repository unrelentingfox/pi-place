#!/usr/bin/env bash
set -uo pipefail

PIPLACE="$(cd "$(dirname "$0")" && pwd)"
PI_DIR="$PIPLACE/pi"
FAILURES=()

# --- Helpers ---

get_upstream_branch() {
	local dir="$1"
	local branch
	if [[ -f "$dir/.pprc" ]]; then
		IFS= read -r branch <"$dir/.pprc"
		branch="${branch//[$'\r\t ']/}"
		echo "${branch:-main}"
	else
		echo "main"
	fi
}

is_pi_core() { [[ "$(basename "$1")" == "pi" ]]; }

has_build_script() {
	local dir="$1"
	jq -e '.scripts.build' "$dir/package.json" &>/dev/null
}

_build_repo() {
	local dir="$1"
	local name
	name="$(basename "$dir")"
	echo "==> $name"
	(
		set -e
		cd "$dir"
		if is_pi_core "$dir"; then
			npm install
			npm run build
			cd "$dir/packages/coding-agent" && npm link
		else
			npm install --ignore-scripts
			if has_build_script "$dir"; then
				npm run build
			fi
			pi install "$dir"
		fi
	)
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
	# Build pi first to ensure it's linked before extensions call `pi install`
	if [[ -z "${1:-}" ]] && [[ -d "$PI_DIR" ]]; then
		_build_repo "$PI_DIR" || FAILURES+=("pi")
		# Now build remaining repos
		for dir in "$PIPLACE"/*/; do
			dir="${dir%/}"
			if [[ ! -d "$dir/.git" && ! -f "$dir/.git" ]]; then
				continue
			fi
			if is_pi_core "$dir"; then
				continue
			fi
			if ! _build_repo "$dir"; then
				FAILURES+=("$(basename "$dir")")
			fi
		done
	else
		for_each_repo _build_repo "${1:-}"
	fi
	report_failures
}

_rebase_one() {
	local dir="$1"
	local name branch
	name="$(basename "$dir")"
	echo "==> $name"
	(
		cd "$dir" || exit 1
		git fetch origin || exit 1
		branch="$(get_upstream_branch "$dir")"
		if ! git rebase --autostash "origin/$branch"; then
			echo "  Rebase failed, aborting."
			git rebase --abort
			exit 1
		fi
	)
}

cmd_rebase() {
	for_each_repo _rebase_one "${1:-}"
	report_failures
}

_reset_one() {
	local dir="$1"
	local name branch
	name="$(basename "$dir")"
	echo "==> $name"
	(
		cd "$dir" || exit 1
		if [[ -n "$(git status --porcelain)" ]]; then
			echo "  Stashing dirty changes..."
			git stash --include-untracked
			echo "  Saved to git stash list."
		fi
		git fetch origin || exit 1
		branch="$(get_upstream_branch "$dir")"
		git reset --hard "origin/$branch"
	)
}

cmd_reset() {
	local scope="${1:-all repos}"
	read -rp "Hard reset $scope to upstream? [y/N] " confirm
	if [[ "$confirm" != [yY] ]]; then
		echo "Aborted."
		return
	fi
	for_each_repo _reset_one "${1:-}"
	report_failures
}

cmd_add() {
	if [[ -z "${1:-}" ]]; then
		echo "Usage: ./pp.sh add <git-url>" >&2
		exit 1
	fi
	local url="$1"
	local name
	name="$(basename "$url" .git)"
	(
		cd "$PIPLACE" || exit 1
		git submodule add "$url" "$name"
		git config -f .gitmodules "submodule.$name.ignore" dirty
	)
	if ! _build_repo "$PIPLACE/$name"; then
		FAILURES+=("$name")
	fi
	report_failures
}

cmd_remove() {
	if [[ -z "${1:-}" ]]; then
		echo "Usage: ./pp.sh remove <name>" >&2
		exit 1
	fi
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
	pi remove "$PIPLACE/$name" || echo "  Warning: pi remove failed, continuing cleanup..."
	(
		cd "$PIPLACE" || exit 1
		git submodule deinit -f "$name"
		git rm -f "$name"
		rm -rf ".git/modules/$name"
	)
}

_status_one() {
	local dir="$1"
	local name
	name="$(basename "$dir")"
	echo "==> $name"
	(
		cd "$dir" || exit 1
		git status --short
		if git rev-parse --abbrev-ref '@{upstream}' &>/dev/null; then
			git rev-list --left-right --count HEAD...'@{upstream}' | awk '{print "ahead: "$1", behind: "$2}'
		fi
		echo ""
	)
}

cmd_status() {
	for_each_repo _status_one "${1:-}"
}

_versions_one() {
	local dir="$1"
	if [[ -f "$dir/package.json" ]]; then
		printf "%-25s %s\n" "$(basename "$dir")" "$(jq -r .version "$dir/package.json")"
	fi
}

cmd_versions() {
	for_each_repo _versions_one "${1:-}"
}

_test_one() {
	local dir="$1"
	local name
	name="$(basename "$dir")"
	echo "==> $name"
	(
		cd "$dir" || exit 1
		if jq -e '.scripts.test' package.json &>/dev/null; then
			npm test
		else
			echo "  (no test script)"
		fi
	)
}

cmd_test() {
	for_each_repo _test_one "${1:-}"
	report_failures
}

_clean_one() {
	local dir="$1"
	local name
	name="$(basename "$dir")"
	echo "==> $name (cleaning)"
	(
		cd "$dir" || exit 1
		rm -rf node_modules
	)
	_build_repo "$dir"
}

cmd_clean() {
	for_each_repo _clean_one "${1:-}"
	report_failures
}

cmd_link() {
	if [[ ! -d "$PI_DIR/packages/coding-agent" ]]; then
		echo "Error: pi core not found at $PI_DIR" >&2
		exit 1
	fi
	echo "==> Linking pi"
	(cd "$PI_DIR/packages/coding-agent" && npm link)
}

usage() {
	cat <<EOF
Usage: ./pp.sh <command> [name]

Commands:
  install [name]    Build and link all (or one) repo
  rebase [name]     Fetch + rebase on upstream (uses --autostash)
  reset [name]      Fetch + hard reset to upstream (stashes dirty changes)
  add <git-url>     Add extension as submodule, build, register
  remove <name>     Unregister, remove submodule
  status [name]     Git status across all (or one) repo
  versions [name]   Show package versions
  test [name]       Run tests
  clean [name]      Nuke node_modules, rebuild
  link              Re-link pi globally
EOF
}

# --- Dispatcher ---

cmd="${1:-}"
shift || true

case "$cmd" in
install) cmd_install "$@" ;;
rebase) cmd_rebase "$@" ;;
reset) cmd_reset "$@" ;;
add) cmd_add "$@" ;;
remove) cmd_remove "$@" ;;
status) cmd_status "$@" ;;
versions) cmd_versions "$@" ;;
test) cmd_test "$@" ;;
clean) cmd_clean "$@" ;;
link) cmd_link ;;
*)
	usage
	[[ -n "$cmd" ]] && exit 1
	;;
esac
