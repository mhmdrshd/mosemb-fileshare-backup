#!/usr/bin/env bash
#
# lib/preflight.sh - SMB connectivity checks, sourced by backup_docs.sh.
#
# Library contract: definitions only. No set/IFS here - a sourced file would
# mutate the caller's shell options. Caller must provide log/err/debug, and
# run_preflight reads the SMB_SERVER and SOURCE_DIRS globals from the config.
# External tools used: getent (glibc), ping (iputils), timeout (coreutils),
# mountpoint (util-linux) - all standard on Arch and WSL.

# Refuse direct execution: when sourced, BASH_SOURCE[0] is this file while $0
# is the caller's name; equal means someone ran it as a script.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "lib/preflight.sh is a library; source it, don't run it" >&2
    exit 2
fi

# check_dns HOST - resolve via NSS (getent), the same lookup path mount.cifs
# uses. nslookup/dig query DNS servers directly and can disagree with
# /etc/hosts or a VPN-hijacked resolver - the exact failure this stage
# exists to catch before it masquerades as an SMB error.
check_dns() {
    local host="$1" result
    if ! result="$(getent hosts "$host")"; then
        err "preflight/dns: cannot resolve '$host' via NSS (resolv.conf? VPN DNS hijack?)"
        return 1
    fi
    debug "preflight/dns: $result"
}

# check_ping HOST - advisory only, never fails the gate: Windows servers
# commonly drop ICMP by firewall default, so a dead ping must not block a
# backup that TCP 445 would prove viable.
check_ping() {
    local host="$1"
    if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
        debug "preflight/ping: $host answered"
    else
        log "preflight/ping: no ICMP reply from $host (advisory only, continuing)"
    fi
}

# check_smb_port HOST [PORT] - TCP connect via bash's /dev/tcp pseudo-device:
# no dependency on any of the three incompatible netcats. PORT defaults to
# 445 and is overridable for tests (445 needs root to listen on).
check_smb_port() {
    local host="$1" port="${2:-445}"
    # timeout is mandatory: a filtered port black-holes the connect for ~2
    # minutes instead of refusing. Host/port ride in as $0/$1 of the inner
    # shell, not interpolated into the command string.
    # shellcheck disable=SC2016  # single quotes deliberate: inner bash expands $0/$1
    if ! timeout 3 bash -c ': >"/dev/tcp/$0/$1"' "$host" "$port" 2>/dev/null; then
        err "preflight/smb: cannot reach TCP $port on $host (firewall, or SMB down)"
        return 1
    fi
    debug "preflight/smb: TCP $port open on $host"
}

# check_mounts DIR... - every source must be a live mountpoint. A dropped
# CIFS share leaves an ordinary empty directory; rsync would read that as
# "source is empty" and mirror the emptiness. Checks all dirs before
# failing, so one run reports every dead mount.
check_mounts() {
    local dir rc=0
    for dir in "$@"; do
        if mountpoint -q -- "$dir"; then
            debug "preflight/mount: $dir is mounted"
        else
            err "preflight/mount: $dir is not a mountpoint (share not mounted?)"
            rc=1
        fi
    done
    return "$rc"
}

# run_preflight - the gate. Triage order learned in the field: name
# resolution first (don't debug SMB until DNS is fixed), reachability,
# then the mounts themselves.
run_preflight() {
    log "preflight: checking $SMB_SERVER"
    check_dns "$SMB_SERVER" || return 1
    check_ping "$SMB_SERVER"
    check_smb_port "$SMB_SERVER" || return 1
    check_mounts "${SOURCE_DIRS[@]}" || return 1
    log "preflight: all checks passed"
}
