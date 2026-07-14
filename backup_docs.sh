#!/usr/bin/env bash
#
# backup_docs.sh - back up documents from SMB shares to an external drive.
# Current stage: strict mode, logging, config loading. No copying yet.

set -Eeuo pipefail
IFS=$'\n\t'

# --- Constants ---------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}" # S{0##*/} strips the path, leaving the filename
readonly SCRIPT_VERSION="0.1.0"

# Where the script itself lives, so config is found no matter the invocation
# directory (cron runs from $HOME, not the repo). Assignment and readonly on
# separate lines: readonly VAR="$(cmd)" would mask a failure of cmd (SC2155).
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly CONFIG_FILE="${SCRIPT_DIR}/backup.conf" # no command subst, inline is safe

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

# --- Config ------------------------------------------------------------------------
# load_config - source CONFIG_FILE and fail fast if required vars are missing.
load_config() {
    if [[ ! -r "$CONFIG_FILE" ]]; then
        err "config not found or unreadable: $CONFIG_FILE"
        err "copy backup.conf.example to backup.conf and edit it"
        exit 1
    fi

    # shellcheck source=backup.conf.example
    # shellcheck disable=SC1091  # following the source needs -x; lint stays flag-free
    source "$CONFIG_FILE"

    # :? fails on unset AND empty - an empty BACKUP_DEST would pass a bare -v test
    : "${BACKUP_DEST:?backup.conf must set BACKUP_DEST}"
    : "${LOG_FILE:?backup.conf must set LOG_FILE}"

    # arrays need a length check; -v guard first, or set -u trips on unset array
    if [[ ! -v SOURCE_DIRS ]] || ((${#SOURCE_DIRS[@]} == 0)); then
        err "backup.conf must set SOURCE_DIRS with at least one directory"
        exit 1
    fi

    debug "config OK: ${#SOURCE_DIRS[@]} source dir(s), dest=$BACKUP_DEST"
}

# --- Functions ---------------------------------------------------------------------
main() {
    log "$SCRIPT_NAME v$SCRIPT_VERSION starting"
    load_config
    log "config loaded from $CONFIG_FILE"
}

# --- Entry point -------------------------------------------------------------------
main "$@"
