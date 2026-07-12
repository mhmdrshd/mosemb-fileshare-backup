#!/usr/bin/env bash
#
# backup_docs.sh - back up documents from SMB shares to an external drive.
# Skeleton: strict mode + entry point only. No functionality yet.

set -Eeuo pipefail
IFS=$'\n\t'

# --- Constants ---------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"     # S{0##*/} strips the path, leaving the filename
readonly SCRIPT_VERSION="0.1.0"

# --- Functions ---------------------------------------------------------------------
main() {
    printf '%s v%s - skeleton, nothing to do yet.\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
}

# --- Entry point -------------------------------------------------------------------
main "$@"