#!/usr/bin/env bats
# check_destination tests. Globals are set directly per test - load_config
# has its own suite; this one isolates the destination gate.

setup() {
    source "${BATS_TEST_DIRNAME}/../backup_docs.sh"
    set +eEu
    # /tmp is a tmpfs mountpoint on this platform - the stand-in for the
    # external drive. BATS_TEST_TMPDIR lives under it.
    BACKUP_MOUNT="/tmp"
    BACKUP_DEST="$BATS_TEST_TMPDIR/dest"
    MIN_FREE_GB=1
    mkdir -p "$BACKUP_DEST"
}

@test "mounted, writable, enough space: passes" {
    run check_destination
    [ "$status" -eq 0 ]
}

@test "unmounted BACKUP_MOUNT is rejected" {
    BACKUP_MOUNT="$BATS_TEST_TMPDIR/notamount"
    mkdir -p "$BACKUP_MOUNT"
    run check_destination
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not mounted"* ]]
}

@test "missing BACKUP_DEST directory is rejected" {
    BACKUP_DEST="$BATS_TEST_TMPDIR/never-created"
    run check_destination
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing or not writable"* ]]
}

@test "space floor rejection prints need vs have" {
    MIN_FREE_GB=999999
    run check_destination
    [ "$status" -eq 1 ]
    [[ "$output" == *"need 999999GB"* ]]
    [[ "$output" == *"have"* ]]
}

@test "MIN_FREE_GB=0 disables the space check" {
    MIN_FREE_GB=0
    run check_destination
    [ "$status" -eq 0 ]
}
