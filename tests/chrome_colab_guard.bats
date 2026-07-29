#!/usr/bin/env bats
# Unit tests for scripts/chrome_colab_guard_v7.sh

load test_helper

setup() {
    setup_sandbox
    load_guard
}

teardown() {
    teardown_sandbox
}

# ── logging ──────────────────────────────────────────────────────────────────

@test "refresh_tick_ts caches a timestamp reused by log" {
    refresh_tick_ts
    [ -n "$LOOP_TS" ]
    log "hello"
    log "world"
    run cat "$LOG_FILE"
    [[ "$output" == *"$LOOP_TS  hello"* ]]
    [[ "$output" == *"$LOOP_TS  world"* ]]
}

# ── prop handling ────────────────────────────────────────────────────────────

@test "prop_enabled defaults to enabled when the prop is unset" {
    stub_command getprop 'exit 0'
    run prop_enabled
    [ "$status" -eq 0 ]
}

@test "prop_enabled is false when the prop is explicitly 0" {
    stub_command getprop 'echo 0'
    run prop_enabled
    [ "$status" -ne 0 ]
}

@test "prop_enabled is true when the prop is 1" {
    stub_command getprop 'echo 1'
    run prop_enabled
    [ "$status" -eq 0 ]
}

# ── memory / tmpfs ───────────────────────────────────────────────────────────

@test "get_mem_available_kb parses MemAvailable" {
    printf 'MemTotal: 4000000 kB\nMemAvailable:  733112 kB\n' > "$MEMINFO_FILE"
    run get_mem_available_kb
    [ "$output" = "733112" ]
}

@test "get_mem_available_kb yields empty output when the field is missing" {
    printf 'MemTotal: 4000000 kB\n' > "$MEMINFO_FILE"
    run get_mem_available_kb
    [ "$output" = "" ]
}

@test "is_tmpfs_mounted only matches the target with fstype tmpfs" {
    printf 'tmpfs %s tmpfs rw 0 0\n' "$TMPFS_TARGET" > "$MOUNTS_FILE"
    run is_tmpfs_mounted
    [ "$status" -eq 0 ]

    printf '/dev/block/x %s ext4 rw 0 0\n' "$TMPFS_TARGET" > "$MOUNTS_FILE"
    run is_tmpfs_mounted
    [ "$status" -ne 0 ]

    printf 'tmpfs /other tmpfs rw 0 0\n' > "$MOUNTS_FILE"
    run is_tmpfs_mounted
    [ "$status" -ne 0 ]
}

@test "mount_tmpfs_if_needed skips when disabled by config" {
    TMPFS_ENABLED=0
    stub_command mount 'echo mounted >> "$SANDBOX/mount.calls"'
    mount_tmpfs_if_needed
    [ ! -f "$SANDBOX/mount.calls" ]
    grep -q "tmpfs disabled by config" "$LOG_FILE"
}

@test "mount_tmpfs_if_needed skips when already mounted" {
    printf 'tmpfs %s tmpfs rw 0 0\n' "$TMPFS_TARGET" > "$MOUNTS_FILE"
    stub_command mount 'echo mounted >> "$SANDBOX/mount.calls"'
    mount_tmpfs_if_needed
    [ ! -f "$SANDBOX/mount.calls" ]
    grep -q "already tmpfs" "$LOG_FILE"
}

@test "mount_tmpfs_if_needed skips when MemAvailable is unreadable" {
    : > "$MEMINFO_FILE"
    stub_command mount 'echo mounted >> "$SANDBOX/mount.calls"'
    mount_tmpfs_if_needed
    [ ! -f "$SANDBOX/mount.calls" ]
    grep -q "MemAvailable unreadable" "$LOG_FILE"
}

@test "mount_tmpfs_if_needed skips below the minimum memory threshold" {
    printf 'MemAvailable: %s kB\n' "$((TMPFS_MIN_MEM_KB - 1))" > "$MEMINFO_FILE"
    stub_command mount 'echo mounted >> "$SANDBOX/mount.calls"'
    mount_tmpfs_if_needed
    [ ! -f "$SANDBOX/mount.calls" ]
    grep -q "tmpfs not mounted" "$LOG_FILE"
}

@test "mount_tmpfs_if_needed mounts when there is enough headroom" {
    printf 'MemAvailable: %s kB\n' "$((TMPFS_MIN_MEM_KB + 1))" > "$MEMINFO_FILE"
    stub_command mount 'printf "%s\n" "$*" >> "$SANDBOX/mount.calls"'
    mount_tmpfs_if_needed
    grep -q -- "-t tmpfs" "$SANDBOX/mount.calls"
    grep -q "size=$TMPFS_SIZE" "$SANDBOX/mount.calls"
    grep -q "mounted tmpfs" "$LOG_FILE"
}

@test "mount_tmpfs_if_needed logs failure when mount fails" {
    printf 'MemAvailable: %s kB\n' "$((TMPFS_MIN_MEM_KB + 1))" > "$MEMINFO_FILE"
    stub_command mount 'exit 1'
    mount_tmpfs_if_needed
    grep -q "tmpfs mount failed" "$LOG_FILE"
}

@test "recheck_tmpfs_safety unmounts below the critical threshold" {
    printf 'tmpfs %s tmpfs rw 0 0\n' "$TMPFS_TARGET" > "$MOUNTS_FILE"
    printf 'MemAvailable: %s kB\n' "$((TMPFS_CRITICAL_MEM_KB - 1))" > "$MEMINFO_FILE"
    stub_command umount 'printf "%s\n" "$*" >> "$SANDBOX/umount.calls"'
    recheck_tmpfs_safety
    grep -q "$TMPFS_TARGET" "$SANDBOX/umount.calls"
    grep -q "tmpfs unmounted" "$LOG_FILE"
}

@test "recheck_tmpfs_safety leaves tmpfs alone above the critical threshold" {
    printf 'tmpfs %s tmpfs rw 0 0\n' "$TMPFS_TARGET" > "$MOUNTS_FILE"
    printf 'MemAvailable: %s kB\n' "$((TMPFS_CRITICAL_MEM_KB + 1))" > "$MEMINFO_FILE"
    stub_command umount 'printf "%s\n" "$*" >> "$SANDBOX/umount.calls"'
    recheck_tmpfs_safety
    [ ! -f "$SANDBOX/umount.calls" ]
}

@test "recheck_tmpfs_safety is a no-op when tmpfs is not mounted" {
    printf 'MemAvailable: 1 kB\n' > "$MEMINFO_FILE"
    stub_command umount 'printf "%s\n" "$*" >> "$SANDBOX/umount.calls"'
    recheck_tmpfs_safety
    [ ! -f "$SANDBOX/umount.calls" ]
}

# ── pid enumeration ──────────────────────────────────────────────────────────

@test "collect_chrome_pids separates main process from children" {
    make_fake_pid 100 "$CHROME_PKG"
    make_fake_pid 101 "$CHROME_PKG:sandboxed_process0"
    make_fake_pid 102 "$CHROME_PKG:privileged_process0"
    collect_chrome_pids
    [ "$MAIN_PIDS" = " 100" ]
    [ "$CHILD_PIDS" = " 101 102" ]
}

@test "collect_chrome_pids ignores lookalike package names" {
    make_fake_pid 200 "${CHROME_PKG}2"
    make_fake_pid 201 "org.example.${CHROME_PKG}"
    collect_chrome_pids
    [ -z "$MAIN_PIDS" ]
    [ -z "$CHILD_PIDS" ]
}

@test "collect_chrome_pids returns empty lists when chrome is not running" {
    make_fake_pid 300 "com.android.systemui"
    collect_chrome_pids
    [ -z "$MAIN_PIDS" ]
    [ -z "$CHILD_PIDS" ]
}

@test "collect_chrome_pids resets state between calls" {
    make_fake_pid 400 "$CHROME_PKG"
    collect_chrome_pids
    [ "$MAIN_PIDS" = " 400" ]
    rm -rf "$PROC_DIR/400"
    collect_chrome_pids
    [ -z "$MAIN_PIDS" ]
}

# ── /proc readers ────────────────────────────────────────────────────────────

@test "read_proc_value reads the first line of a readable file" {
    printf 'first\nsecond\n' > "$SANDBOX/value"
    run read_proc_value "$SANDBOX/value"
    [ "$status" -eq 0 ]
    [ "$output" = "first" ]
}

@test "read_proc_value fails for a missing file" {
    run read_proc_value "$SANDBOX/nope"
    [ "$status" -ne 0 ]
}

@test "read_proc_nice parses nice from a normal stat line" {
    make_fake_pid 500 "$CHROME_PKG" 0 -10
    run read_proc_nice 500
    [ "$output" = "-10" ]
}

@test "read_proc_nice parses nice when comm contains a space and a paren" {
    make_fake_pid 501 "$CHROME_PKG" 0 -5 "GLThread (61)"
    run read_proc_nice 501
    [ "$output" = "-5" ]
}

@test "read_proc_nice fails for an unknown pid" {
    run read_proc_nice 9999999
    [ "$status" -ne 0 ]
}

# ── tuning ───────────────────────────────────────────────────────────────────

@test "apply_pid_tuning writes oom_score_adj and renices a drifted pid" {
    make_fake_pid 600 "$CHROME_PKG" 0 0
    stub_command renice 'printf "%s\n" "$*" >> "$SANDBOX/renice.calls"'
    run apply_pid_tuning 600 "$MAIN_OOM_SCORE" "$MAIN_NICE_LEVEL"
    [ "$status" -eq 0 ]
    [ "$(cat "$PROC_DIR/600/oom_score_adj")" = "$MAIN_OOM_SCORE" ]
    grep -q -- "$MAIN_NICE_LEVEL -p 600" "$SANDBOX/renice.calls"
}

@test "apply_pid_tuning returns 2 when the pid already has target values" {
    make_fake_pid 601 "$CHROME_PKG" "$CHILD_OOM_SCORE" "$CHILD_NICE_LEVEL"
    stub_command renice 'printf "%s\n" "$*" >> "$SANDBOX/renice.calls"'
    run apply_pid_tuning 601 "$CHILD_OOM_SCORE" "$CHILD_NICE_LEVEL"
    [ "$status" -eq 2 ]
    [ ! -f "$SANDBOX/renice.calls" ]
}

@test "apply_pid_tuning fails for a dead pid" {
    run apply_pid_tuning 9999999 "$MAIN_OOM_SCORE" "$MAIN_NICE_LEVEL"
    [ "$status" -eq 1 ]
}

@test "apply_pid_tuning logs a warning when renice fails" {
    make_fake_pid 602 "$CHROME_PKG" "$MAIN_OOM_SCORE" 0
    stub_command renice 'exit 1'
    apply_pid_tuning 602 "$MAIN_OOM_SCORE" "$MAIN_NICE_LEVEL" || true
    grep -q "renice failed" "$LOG_FILE"
}

@test "tune_if_needed tunes an untracked pid and records its tier tag" {
    make_fake_pid 700 "$CHROME_PKG" 0 0
    stub_command renice 'exit 0'
    tune_if_needed 700 main "$MAIN_OOM_SCORE" "$MAIN_NICE_LEVEL"
    [ "$(cat "$STATE_DIR/700")" = "main:$MAIN_OOM_SCORE:$MAIN_NICE_LEVEL" ]
    [ "$(cat "$PROC_DIR/700/oom_score_adj")" = "$MAIN_OOM_SCORE" ]
}

@test "tune_if_needed skips rewriting a pid that is already in the target state" {
    make_fake_pid 701 "$CHROME_PKG" "$CHILD_OOM_SCORE" "$CHILD_NICE_LEVEL"
    printf 'child:%s:%s\n' "$CHILD_OOM_SCORE" "$CHILD_NICE_LEVEL" > "$STATE_DIR/701"
    stub_command renice 'printf "%s\n" "$*" >> "$SANDBOX/renice.calls"'
    tune_if_needed 701 child "$CHILD_OOM_SCORE" "$CHILD_NICE_LEVEL"
    [ ! -f "$SANDBOX/renice.calls" ]
}

@test "tune_if_needed re-tunes a pid whose values drifted" {
    make_fake_pid 702 "$CHROME_PKG" 0 0
    printf 'main:%s:%s\n' "$MAIN_OOM_SCORE" "$MAIN_NICE_LEVEL" > "$STATE_DIR/702"
    stub_command renice 'exit 0'
    tune_if_needed 702 main "$MAIN_OOM_SCORE" "$MAIN_NICE_LEVEL"
    [ "$(cat "$PROC_DIR/702/oom_score_adj")" = "$MAIN_OOM_SCORE" ]
}

@test "tune_if_needed re-evaluates a pid whose tier tag changed" {
    make_fake_pid 703 "$CHROME_PKG" "$MAIN_OOM_SCORE" 0
    printf 'main:%s:%s\n' "$MAIN_OOM_SCORE" "$MAIN_NICE_LEVEL" > "$STATE_DIR/703"
    stub_command renice 'exit 0'
    tune_if_needed 703 child "$CHILD_OOM_SCORE" "$CHILD_NICE_LEVEL"
    [ "$(cat "$STATE_DIR/703")" = "child:$CHILD_OOM_SCORE:$CHILD_NICE_LEVEL" ]
    [ "$(cat "$PROC_DIR/703/oom_score_adj")" = "$CHILD_OOM_SCORE" ]
}

# ── state pruning ────────────────────────────────────────────────────────────

@test "prune_stale_state removes entries for dead pids only" {
    make_fake_pid 800 "$CHROME_PKG"
    printf 'main:x:y\n' > "$STATE_DIR/800"
    printf 'main:x:y\n' > "$STATE_DIR/801"
    prune_stale_state
    [ -f "$STATE_DIR/800" ]
    [ ! -f "$STATE_DIR/801" ]
}

@test "prune_stale_state tolerates an empty state directory" {
    run prune_stale_state
    [ "$status" -eq 0 ]
}

# ── lock handling ────────────────────────────────────────────────────────────

@test "acquire_lock creates the lock dir and records our pid" {
    acquire_lock
    [ -d "$LOCK_DIR" ]
    [ "$(cat "$LOCK_DIR/pid")" = "$$" ]
}

@test "acquire_lock steals a lock left behind by a dead pid" {
    mkdir -p "$LOCK_DIR"
    printf '9999999\n' > "$LOCK_DIR/pid"
    acquire_lock
    [ "$(cat "$LOCK_DIR/pid")" = "$$" ]
}

@test "acquire_lock exits 0 when another live instance holds the lock" {
    mkdir -p "$LOCK_DIR"
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    run acquire_lock
    [ "$status" -eq 0 ]
    grep -q "already running with PID=$$" "$LOG_FILE"
}

# ── boot wait ────────────────────────────────────────────────────────────────

@test "wait_for_boot returns as soon as sys.boot_completed is 1" {
    stub_command getprop 'echo 1'
    run wait_for_boot
    [ "$status" -eq 0 ]
    grep -q "boot completed" "$LOG_FILE"
}

@test "wait_for_boot warns and continues after the timeout" {
    BOOT_WAIT_SECS=2
    stub_command getprop 'echo 0'
    stub_command sleep 'exit 0'
    run wait_for_boot
    [ "$status" -eq 0 ]
    grep -q "boot wait timeout reached" "$LOG_FILE"
}
