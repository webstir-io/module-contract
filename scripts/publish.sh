#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/publish.sh <patch|minor|major|x.y.z> [--contract-version x.y.z]

Examples:
  scripts/publish.sh patch
  scripts/publish.sh 0.2.0

The script requires a clean git worktree and an npm login to
https://npm.pkg.github.com with write:packages access.
EOF
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

main() {
  if [[ $# -lt 1 ]]; then
    echo "error: version bump argument missing" >&2
    usage
  fi

  local bump="$1"; shift || true
  local contract_version=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --contract-version)
        shift
        contract_version="${1:-}"
        ;;
      *)
        echo "error: unknown option '$1'" >&2
        usage
        ;;
    esac
    shift || true
  done
  if [[ ! $bump =~ ^(patch|minor|major)$ && ! $bump =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid bump '$bump'" >&2
    usage
  fi

  ensure_clean_git

  cd "$ROOT_DIR"

  echo "› npm version $bump"
  npm version "$bump"

  if [[ -n "$contract_version" ]]; then
    echo "› Updating CONTRACT_VERSION to $contract_version"
    update_contract_version "$contract_version"
  fi

  echo "› npm run build"
  npm run build

  echo "› npm run test"
  npm run test

  # Do not publish from this script. Release workflow owns publish.
  echo "› Skipping direct npm publish; pushing commit+tag will trigger the release workflow."

  echo
  # If running in CI or without a TTY, skip the interactive prompt unless auto-push requested.
  if [[ -n "${CI:-}" || ! -t 0 ]]; then
    if [[ "${PUBLISH_AUTO_PUSH:-}" =~ ^([Yy][Ee][Ss]|[Yy]|1|true)$ ]]; then
      echo "› git push"
      git push
      echo "› git push --tags"
      git push --tags
    else
      echo "No TTY detected; skipping git push prompt."
      echo "Set PUBLISH_AUTO_PUSH=1 to push commit and tags automatically."
    fi;
    return 0
  fi

  # Interactive shell: ask the user.
  read -r -p "Push git commit and tag upstream? [y/N]: " reply || true
  if [[ "$reply" =~ ^[Yy](es)?$ ]]; then
    echo "› git push"
    git push
    echo "› git push --tags"
    git push --tags
  else
    echo "Skipping push. To publish upstream later, run:"
    echo "  git push && git push --tags"
  fi
}

ensure_clean_git() {
  cd "$ROOT_DIR"
  if ! git diff --quiet --ignore-submodules HEAD; then
    echo "error: git worktree has uncommitted changes" >&2
    exit 1
  fi
  if ! git diff --quiet --cached --ignore-submodules; then
    echo "error: git index has staged changes" >&2
    exit 1
  fi
}

update_contract_version() {
  local new_ver="$1"
  if [[ ! $new_ver =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid contract version '$new_ver'" >&2
    exit 1
  fi
  local file="${ROOT_DIR}/src/index.ts"
  if [[ ! -f "$file" ]]; then
    echo "error: cannot find $file to update CONTRACT_VERSION" >&2
    exit 1
  fi
  # Replace the export line
  sed -i'' -E "s|^export const CONTRACT_VERSION = '[0-9]+\.[0-9]+\.[0-9]+' as const;|export const CONTRACT_VERSION = '${new_ver}' as const;|" "$file"
  echo "› CONTRACT_VERSION updated in src/index.ts"
}

main "$@"
