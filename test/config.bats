#!/usr/bin/env bats
# load_config tests. Each test writes its own config into BATS_TEST_TMPDIR
# and points CONFIG_FILE at it (still a plain global when sourced - main()
# is what makes it readonly, and main never runs here).

setup() {
    source "${BATS_TEST_DIRNAME}/../backup_docs.sh"
    set +eEu
    CONFIG_FILE="$BATS_TEST_TMPDIR/backup.conf"
}

# write_config - a known-good config; tests then break one thing each.
# BACKUP_DEST sits under /tmp so the under-mount validation holds.
write_config() {
    mkdir -p "$BATS_TEST_TMPDIR/dest"
    cat >"$CONFIG_FILE" <<EOF
SOURCE_DIRS=(/tmp)
SMB_SERVER="localhost"
BACKUP_MOUNT="/tmp"
BACKUP_DEST="$BATS_TEST_TMPDIR/dest"
MIN_FREE_GB=1
LOG_FILE="$BATS_TEST_TMPDIR/log"
EOF
}

@test "valid config loads" {
    write_config
    run load_config
    [ "$status" -eq 0 ]
}

@test "missing config file fails with the copy hint" {
    run load_config
    [ "$status" -eq 1 ]
    [[ "$output" == *"copy backup.conf.example"* ]]
}

@test "missing scalar variable dies naming it" {
    write_config
    sed -i '/^SMB_SERVER=/d' "$CONFIG_FILE"
    run load_config
    [ "$status" -ne 0 ]
    [[ "$output" == *"must set SMB_SERVER"* ]]
}

@test "empty SOURCE_DIRS array is rejected" {
    write_config
    sed -i 's/^SOURCE_DIRS=.*/SOURCE_DIRS=()/' "$CONFIG_FILE"
    run load_config
    [ "$status" -eq 1 ]
    [[ "$output" == *"at least one directory"* ]]
}

@test "non-numeric MIN_FREE_GB is rejected at load" {
    write_config
    sed -i 's/^MIN_FREE_GB=.*/MIN_FREE_GB=abc/' "$CONFIG_FILE"
    run load_config
    [ "$status" -eq 1 ]
    [[ "$output" == *"whole number"* ]]
}

@test "BACKUP_DEST outside BACKUP_MOUNT is rejected" {
    write_config
    sed -i 's|^BACKUP_DEST=.*|BACKUP_DEST="/home/elsewhere"|' "$CONFIG_FILE"
    run load_config
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not under BACKUP_MOUNT"* ]]
}

@test "BACKUP_DEST equal to BACKUP_MOUNT is accepted" {
    write_config
    sed -i 's|^BACKUP_DEST=.*|BACKUP_DEST="/tmp"|' "$CONFIG_FILE"
    run load_config
    [ "$status" -eq 0 ]
}
