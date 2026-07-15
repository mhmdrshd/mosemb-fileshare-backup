#!/usr/bin/env bats
# parse_args tests. The script is sourced, not executed: the entry-point
# guard keeps main() from running, so functions are callable directly.

setup() {
    source "${BATS_TEST_DIRNAME}/../backup_docs.sh"
    # Strict mode is process state and came along with the source; relax the
    # parts that fight the bats harness (nounset trips bats internals,
    # errexit hides which assertion failed).
    set +eEu
}

@test "-h exits 0 and prints usage" {
    run parse_args -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "bundled -nv sets both flags" {
    parse_args -nv
    [ "$DRY_RUN" -eq 1 ]
    [ "$VERBOSE" -eq 1 ]
}

@test "-c overrides CONFIG_FILE" {
    parse_args -c /some/where/backup.conf
    [ "$CONFIG_FILE" = "/some/where/backup.conf" ]
}

@test "bare -c exits 2 and names the flag" {
    run parse_args -c
    [ "$status" -eq 2 ]
    [[ "$output" == *"option -c requires an argument"* ]]
}

@test "unknown option exits 2" {
    run parse_args -x
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option: -x"* ]]
}

@test "stray positional argument exits 2" {
    run parse_args -n /mnt/typo
    [ "$status" -eq 2 ]
    [[ "$output" == *"unexpected argument: /mnt/typo"* ]]
}

@test "parse_args works when called twice (local OPTIND)" {
    # The milestone-4 insurance, cashed in: without local OPTIND the second
    # call would resume past its own arguments and parse nothing.
    parse_args -n
    parse_args -v
    [ "$VERBOSE" -eq 1 ]
}
