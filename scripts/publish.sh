#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/publish.sh <patch|minor|major|x.y.z> [--contract-version x.y.z] [--no-push]

Examples:
  scripts/publish.sh patch
  scripts/publish.sh 0.2.0

The script requires a clean git worktree and an npm login to
https://npm.pkg.github.com with write:packages access.

By default, the script pushes the version bump commit and tag. To skip pushing,
pass --no-push or set PUBLISH_NO_PUSH=1.
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
  local no_push="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --contract-version)
        shift
        contract_version="${1:-}"
        ;;
      --no-push)
        no_push="true"
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

  if [[ "$no_push" == "true" || "${PUBLISH_NO_PUSH:-}" =~ ^([Yy][Ee][Ss]|[Yy]|1|true)$ ]]; then
    echo "› Skipping git push (no-push)."
    echo "  To publish upstream later, run: git push && git push --tags"
    return 0
  fi

  echo "› git push"
  git push
  echo "› git push --tags"
  git push --tags
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
