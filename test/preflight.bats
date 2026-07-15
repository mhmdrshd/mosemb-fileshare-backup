#!/usr/bin/env bats
# lib/preflight.sh unit tests. The library contract - caller provides the
# loggers - is what makes this file possible: three stubs and a source.

setup() {
    log() { echo "LOG $*"; }
    err() { echo "ERR $*" >&2; }
    debug() { :; }
    source "${BATS_TEST_DIRNAME}/../lib/preflight.sh"
}

@test "refuses direct execution" {
    run bash "${BATS_TEST_DIRNAME}/../lib/preflight.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"source it"* ]]
}

@test "check_dns resolves localhost" {
    run check_dns localhost
    [ "$status" -eq 0 ]
}

@test "check_dns fails on a bogus host" {
    run check_dns no-such-host.invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot resolve"* ]]
}

@test "check_ping is advisory: bogus host still returns 0" {
    run check_ping no-such-host.invalid
    [ "$status" -eq 0 ]
    [[ "$output" == *"advisory only"* ]]
}

@test "check_smb_port succeeds against a live port" {
    python3 -m http.server 18445 --bind 127.0.0.1 >/dev/null 2>&1 &
    listener=$!
    sleep 0.3
    run check_smb_port 127.0.0.1 18445
    kill "$listener"
    [ "$status" -eq 0 ]
}

@test "check_smb_port fails on a closed port" {
    run check_smb_port 127.0.0.1 18446
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot reach TCP 18446"* ]]
}

@test "check_mounts accepts real mountpoints" {
    run check_mounts / /proc
    [ "$status" -eq 0 ]
}

@test "check_mounts reports every dead mount, not just the first" {
    mkdir -p "$BATS_TEST_TMPDIR/a" "$BATS_TEST_TMPDIR/b"
    run check_mounts "$BATS_TEST_TMPDIR/a" "$BATS_TEST_TMPDIR/b"
    [ "$status" -eq 1 ]
    [ "$(grep -c 'not a mountpoint' <<<"$output")" -eq 2 ]
}
