#!/usr/bin/env bash
#
# backup_docs.sh - back up documents from SMB shares to an external drive.
# Skeleton: strict mode + entry point only. No functionality yet.

set -Eeuo pipefail
IFS=$'\n\t'

# --- Constants ---------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}" # S{0##*/} strips the path, leaving the filename
readonly SCRIPT_VERSION="0.1.0"

# --- Logging -----------------------------------------------------------------------
# 0 = quiet, 1 = show debug messages. Env-var hook until getopts lands (milestone 4):
#   VERBOSE=1 ./backup_docs.sh
VERBOSE="${VERBOSE:-0}"

# log MESSAGE... - timestamped info line on stdout.
log() {
    local IFS=' ' # "$*" joins args with the first char of IFS; global IFS is \n\t
    printf '[%(%F %T)T] [INFO] %s\n' -1 "$*"
}

# err MESSAGE... - timestamped error line on stderr.
err() {
    local IFS=' '
    printf '[%(%F %T)T] [ERROR] %s: %s\n' -1 "$SCRIPT_NAME" "$*" >&2
}

# debug MESSAGE... - timestamped debug line on stderr, only when VERBOSE=1.
debug() {
    if ((VERBOSE)); then
        local IFS=' '
        printf '[%(%F %T)T] [DEBUG] %s\n' -1 "$*" >&2
    fi
}

# --- Functions ---------------------------------------------------------------------
main() {
    log "$SCRIPT_NAME v$SCRIPT_VERSION starting"
    debug "verbose mode on (VERBOSE=$VERBOSE)"
    err "demo error - nothing is actually wrong" # temporary, proves stderr routing
    log "nothing to do yet"
}

# --- Entry point -------------------------------------------------------------------
main "$@"
