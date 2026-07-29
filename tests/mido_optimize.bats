#!/usr/bin/env bats
# Unit tests for mido_optimize.sh helpers and script invariants.

load test_helper

setup() {
    setup_sandbox
    load_mido
}

teardown() {
    teardown_sandbox
}

@test "sourcing initialises the logfile with a start banner" {
    grep -q "mido Optimize v3.0 Start" "$MIDO_OPTIMIZE_LOG"
}

@test "log writes a timestamped line to stdout and the logfile" {
    run log "hello world"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]\ hello\ world$ ]]
    grep -q "hello world" "$MIDO_OPTIMIZE_LOG"
}

@test "log appends rather than truncating" {
    log "first" > /dev/null
    log "second" > /dev/null
    grep -q "first" "$MIDO_OPTIMIZE_LOG"
    grep -q "second" "$MIDO_OPTIMIZE_LOG"
}

@test "check_node succeeds for an existing file" {
    : > "$SANDBOX/node"
    run check_node "$SANDBOX/node"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "check_node succeeds for an existing directory" {
    run check_node "$SANDBOX"
    [ "$status" -eq 0 ]
}

@test "check_node fails and logs a SKIP for a missing node" {
    run check_node "$SANDBOX/missing"
    [ "$status" -eq 1 ]
    [[ "$output" == *"SKIP: $SANDBOX/missing not present"* ]]
    grep -q "SKIP: $SANDBOX/missing not present" "$MIDO_OPTIMIZE_LOG"
}

@test "check_node with an empty argument fails" {
    run check_node ""
    [ "$status" -eq 1 ]
}

@test "the two copies of mido_optimize.sh stay in sync" {
    run diff "$REPO_ROOT/mido_optimize.sh" "$REPO_ROOT/scripts/mido_optimize.sh"
    [ "$status" -eq 0 ]
}

@test "post-fs-data.sh execs the packaged optimize script" {
    grep -q 'exec "\$MODDIR/scripts/mido_optimize.sh"' "$REPO_ROOT/post-fs-data.sh"
}

@test "all shell scripts parse cleanly" {
    for f in "$REPO_ROOT"/*.sh "$REPO_ROOT"/scripts/*.sh; do
        run sh -n "$f"
        [ "$status" -eq 0 ]
    done
}
