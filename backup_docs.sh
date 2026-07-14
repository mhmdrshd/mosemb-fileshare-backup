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
# Default config path. Not readonly here: -c must be able to override it, so
# main() freezes it with readonly only after parse_args has run.
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"

# --- Defaults (flags flip these in parse_args) ---------------------------------------
VERBOSE=0 # -v: show debug messages
DRY_RUN=0 # -n: report what would be copied, touch nothing (consumed in milestone 6)

# --- Logging -----------------------------------------------------------------------

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
    : "${SMB_SERVER:?backup.conf must set SMB_SERVER}"
    : "${BACKUP_DEST:?backup.conf must set BACKUP_DEST}"
    : "${LOG_FILE:?backup.conf must set LOG_FILE}"

    # arrays need a length check; -v guard first, or set -u trips on unset array
    if [[ ! -v SOURCE_DIRS ]] || ((${#SOURCE_DIRS[@]} == 0)); then
        err "backup.conf must set SOURCE_DIRS with at least one directory"
        exit 1
    fi

    debug "config OK: ${#SOURCE_DIRS[@]} source dir(s), dest=$BACKUP_DEST"
}

# --- Libraries ---------------------------------------------------------------------
# Sourcing only defines the check_* functions; nothing runs until main() calls
# run_preflight. SCRIPT_DIR (not a relative path) so it works from any cwd.
# shellcheck source=lib/preflight.sh
# shellcheck disable=SC1091  # following the source needs -x; lint stays flag-free
source "${SCRIPT_DIR}/lib/preflight.sh"

# --- CLI ---------------------------------------------------------------------------
# usage - print help. Goes to stdout: -h is a request, not an error, so
# `backup_docs.sh -h | less` must work. Error paths redirect it to stderr.
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [-n] [-v] [-c CONFIG] [-h]

Back up documents from SMB shares to an external drive.

Options:
  -n           dry-run: show what would be copied, change nothing
  -v           verbose: show debug messages
  -c CONFIG    config file to use (default: $CONFIG_FILE)
  -h           show this help and exit
EOF
}

# parse_args - set DRY_RUN, VERBOSE, CONFIG_FILE from the command line.
parse_args() {
    # OPTIND is global and survives between getopts runs; without local, a
    # second call (bats tests, milestone 8) would resume mid-argument-list.
    local opt OPTIND

    # Leading ':' = silent mode: bash hands errors to us as ':' and '?' cases
    # instead of printing its own untimestamped message. 'c:' = -c takes a value.
    while getopts ":nvc:h" opt; do
        case "$opt" in
            n) DRY_RUN=1 ;;
            v) VERBOSE=1 ;;
            c) CONFIG_FILE="$OPTARG" ;;
            h)
                usage
                exit 0
                ;;
            :) # a flag that needs a value didn't get one; OPTARG = the flag char
                err "option -$OPTARG requires an argument"
                usage >&2
                exit 2
                ;;
            \?) # unknown flag; OPTARG = the offending char
                err "unknown option: -$OPTARG"
                usage >&2
                exit 2
                ;;
        esac
    done
    shift $((OPTIND - 1))

    # Leftover positional args are a user mistake; ignoring them silently would
    # let './backup_docs.sh -n /mnt/typo' pretend that path meant something.
    if (($# > 0)); then
        err "unexpected argument: $1 (this script takes no positional arguments)"
        usage >&2
        exit 2
    fi
}

# --- Functions ---------------------------------------------------------------------
main() {
    parse_args "$@"
    readonly CONFIG_FILE # -c had its chance; frozen from here on

    log "$SCRIPT_NAME v$SCRIPT_VERSION starting"
    debug "flags: DRY_RUN=$DRY_RUN VERBOSE=$VERBOSE CONFIG_FILE=$CONFIG_FILE"
    if ((DRY_RUN)); then
        log "dry-run mode: no files will be copied"
    fi
    load_config
    log "config loaded from $CONFIG_FILE"

    if ! run_preflight; then
        err "preflight failed - backup aborted"
        exit 1
    fi
}

# --- Entry point -------------------------------------------------------------------
main "$@"
