#!/bin/sh
set -eu

config_key="workout.secretsXcconfigSource"

usage() {
  cat >&2 <<'EOF'
usage: scripts/install-worktree-bootstrap.sh [--source /absolute/path/to/Secrets.xcconfig]

Installs the tracked post-checkout hook for this repo and backfills existing
worktrees with Secrets.xcconfig when a trusted source is available.
EOF
}

absolute_path() {
  input="$1"
  case "$input" in
    /*) printf '%s\n' "$input" ;;
    *)
      dir="$(dirname "$input")"
      base="$(basename "$input")"
      printf '%s/%s\n' "$(cd "$dir" && pwd)" "$base"
      ;;
  esac
}

source_path=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      source_path="$(absolute_path "$2")"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(git -C "$script_dir/.." rev-parse --show-toplevel)"
bootstrap="$repo_root/scripts/bootstrap-xcode-worktree.sh"

git -C "$repo_root" config core.hooksPath .githooks

if [ -n "$source_path" ]; then
  [ -f "$source_path" ] || {
    printf '%s\n' "install-worktree-bootstrap: source does not point to a file: $source_path" >&2
    exit 1
  }
  git -C "$repo_root" config "$config_key" "$source_path"
fi

git -C "$repo_root" worktree list --porcelain | while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      worktree_path="${line#worktree }"
      "$bootstrap" "$worktree_path"
      ;;
  esac
done

printf '%s\n' "install-worktree-bootstrap: installed core.hooksPath=.githooks"
