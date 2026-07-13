#!/usr/bin/env bash
#
# rsync_guard.sh -- PreToolUse hook: block rsync commands that lack a dry-run flag.
#
# Exit contract:
#   0 - no objection (not rsync, or dry-run present)
#   2 - block; reason on stderr
#   other - hook error; Claude Code proceeds anyway (fails open)

set -Eeuo pipefail
IFS=$'\n\t'

# Unexpected failures would exit non-2 and fail open; convert them to blocks
trap 'echo "rsync_guard: internal error; failing closed." >&2; exit 2' ERR

main() {
  local input cmd
  input=$(cat)
  cmd=$(jq -r '.tool_input.command // empty' <<<"$input")

  # Not rsync in anywhere in the command: nothing to check
  if [[ ! $cmd =~ (^|[[:space:]]|/)rsync([[:space:]]|$) ]]; then
    exit 0
  fi
  
  # Dry run present: long form, or -n standalone/bundled (-n, -avn)
  if [[ $cmd =~ (^|[[:space:]])--dry-run([[:space:]]|$) ]] || [[ $cmd =~ (^|[[:space:]])-[a-zA-Z]*n ]]; then
    exit 0
  fi

  echo "Blocked: rsync without --dry-run. Add -n or ask Muhammad Rasheed." >&2
  exit 2
}

main "$@"
