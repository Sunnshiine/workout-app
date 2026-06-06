#!/bin/sh
set -eu

secrets_filename="Secrets.xcconfig"
template_filename="Secrets.xcconfig.template"
config_key="workout.secretsXcconfigSource"

log() {
  printf '%s\n' "xcode-worktree-bootstrap: $*" >&2
}

fail() {
  log "$*"
  exit 1
}

repo_root_for() {
  target="$1"
  git -C "$target" rev-parse --show-toplevel 2>/dev/null
}

copy_secret() {
  source_path="$1"
  destination="$2/$secrets_filename"
  label="$3"

  cp "$source_path" "$destination" || fail "failed to copy $secrets_filename from $label"
  log "copied $secrets_filename from $label"
}

main_worktree_secret() {
  target="$1"
  git -C "$target" worktree list --porcelain 2>/dev/null | awk -v filename="$secrets_filename" '
    /^worktree / {
      path = substr($0, 10)
      next
    }
    /^branch refs\/heads\/main$/ {
      if (path != "") {
        print path "/" filename
        exit
      }
    }
  '
}

target="${1:-}"
if [ -z "$target" ]; then
  target="$(repo_root_for ".")" || exit 0
else
  target="$(repo_root_for "$target")" || fail "not a git worktree: $target"
fi

if [ -f "$target/$secrets_filename" ]; then
  exit 0
fi

if [ -n "${SECRETS_XCCONFIG_SOURCE:-}" ]; then
  if [ ! -f "$SECRETS_XCCONFIG_SOURCE" ]; then
    fail "SECRETS_XCCONFIG_SOURCE is set but does not point to a file"
  fi
  copy_secret "$SECRETS_XCCONFIG_SOURCE" "$target" "SECRETS_XCCONFIG_SOURCE"
  exit 0
fi

if configured_source="$(git -C "$target" config --get "$config_key" 2>/dev/null)"; then
  if [ -n "$configured_source" ]; then
    if [ ! -f "$configured_source" ]; then
      fail "$config_key is set but does not point to a file"
    fi
    copy_secret "$configured_source" "$target" "$config_key"
    exit 0
  fi
fi

main_secret="$(main_worktree_secret "$target")"
if [ -n "$main_secret" ] && [ -f "$main_secret" ]; then
  copy_secret "$main_secret" "$target" "main worktree"
  exit 0
fi

if [ -f "$target/$template_filename" ]; then
  cp "$target/$template_filename" "$target/$secrets_filename" \
    || fail "failed to create $secrets_filename from $template_filename"
  log "created $secrets_filename from template; live Google auth is not configured"
  exit 0
fi

log "no $secrets_filename source found; Xcode app-target builds may fail"
exit 0
