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

# Document patterns for rsync filters. Character classes because rsync has no
# case-insensitive matching and Windows users produce .PDF and .Doc too - a
# plain *.pdf filter would silently skip those forever.
readonly DOC_PATTERNS=('*.[pP][dD][fF]' '*.[dD][oO][cC]' '*.[dD][oO][cC][xX]')

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
    : "${BACKUP_MOUNT:?backup.conf must set BACKUP_MOUNT}"
    : "${MIN_FREE_GB:?backup.conf must set MIN_FREE_GB}"
    : "${LOG_FILE:?backup.conf must set LOG_FILE}"

    # Validate at load, not at use: garbage here would otherwise surface as a
    # bash arithmetic syntax error deep inside the space check.
    if [[ ! "$MIN_FREE_GB" =~ ^[0-9]+$ ]]; then
        err "MIN_FREE_GB must be a whole number of GB, got: '$MIN_FREE_GB'"
        exit 1
    fi

    # Unquoted /* on the right of == is a glob, not a string. Catches a config
    # where dest and mount silently disagree (dest would land on the root fs).
    if [[ "$BACKUP_DEST" != "$BACKUP_MOUNT" && "$BACKUP_DEST" != "$BACKUP_MOUNT"/* ]]; then
        err "BACKUP_DEST ($BACKUP_DEST) is not under BACKUP_MOUNT ($BACKUP_MOUNT)"
        exit 1
    fi

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

# --- Destination -------------------------------------------------------------------
# check_destination - dest-side mirror of the preflight. The trap: an absent
# external drive leaves BACKUP_MOUNT as a plain directory, and a "successful"
# backup quietly fills the root filesystem instead of reaching the drive.
check_destination() {
    if ! mountpoint -q -- "$BACKUP_MOUNT"; then
        err "destination: $BACKUP_MOUNT is not mounted (external drive absent?)"
        return 1
    fi

    if [[ ! -d "$BACKUP_DEST" || ! -w "$BACKUP_DEST" ]]; then
        err "destination: $BACKUP_DEST missing or not writable (create it once, on the mounted drive)"
        return 1
    fi

    local avail_bytes need_bytes
    avail_bytes="$(df --output=avail -B1 -- "$BACKUP_DEST" | tail -n 1)"
    need_bytes=$((MIN_FREE_GB * 1024 ** 3))
    if ((avail_bytes < need_bytes)); then
        err "destination: need ${MIN_FREE_GB}GB free at $BACKUP_DEST, have $((avail_bytes / 1024 ** 3))GB"
        return 1
    fi
    debug "destination OK: mounted, writable, $((avail_bytes / 1024 ** 3))GB free (floor ${MIN_FREE_GB}GB)"
}

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

# --- Backup ------------------------------------------------------------------------
# run_backup - rsync each source into BACKUP_DEST/<basename of source>.
# Two sources with the same basename would collide there; fine for the
# current share layout, revisit if SOURCE_DIRS ever gains twins.
run_backup() {
    local src pat rc=0
    for src in "${SOURCE_DIRS[@]}"; do
        # Array-as-command: each element stays exactly one argument, spaces
        # and all. A string here would re-split 'Q3 Reports' into two words.
        # -rt, not -a: CIFS ownership is synthetic (set by mount options), so
        # preserving owner/group/perms is meaningless and needs root at dest.
        local cmd=(rsync -rt --prune-empty-dirs --include='*/')
        for pat in "${DOC_PATTERNS[@]}"; do
            cmd+=(--include="$pat")
        done
        cmd+=(--exclude='*')
        if ((DRY_RUN)); then
            cmd+=(--dry-run --itemize-changes)
        fi
        if ((VERBOSE)); then
            cmd+=(--verbose)
        fi
        # Trailing slash on the source: copy its contents, not the directory
        # itself - dest layout stays BACKUP_DEST/<share>/<files> either way.
        cmd+=("${src}/" "${BACKUP_DEST}/$(basename -- "$src")/")

        log "backup: $src"
        debug "rsync cmd: ${cmd[*]}"
        if "${cmd[@]}"; then
            log "backup done: $src"
        else
            err "rsync failed for $src (exit $?)"
            rc=1
        fi
    done
    return "$rc"
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

    if ! check_destination; then
        err "destination check failed - backup aborted"
        exit 1
    fi

    if ! run_backup; then
        err "backup finished with errors"
        exit 1
    fi
    log "backup complete"
    if ((DRY_RUN)); then
        log "dry-run: nothing was actually copied"
    fi
}

# --- Entry point -------------------------------------------------------------------
# Run main only when executed; sourcing (tests, milestone 8) just gets the
# function definitions. Same BASH_SOURCE test the lib uses, inverted.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
