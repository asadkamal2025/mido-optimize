#!/usr/bin/env bash
# Shared helpers for the bats suites.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Creates a per-test sandbox directory and exports it as $SANDBOX.
setup_sandbox() {
    SANDBOX="$(mktemp -d)"
    export SANDBOX
}

teardown_sandbox() {
    [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
}

# Creates a fake /proc/<pid> entry with the given cmdline (NUL-terminated,
# like the kernel produces), oom_score_adj and stat line.
make_fake_pid() {
    local pid="$1" cmdline="$2" oom="${3:-0}" nice="${4:-0}" comm="${5:-chrome}"
    local dir="$SANDBOX/proc/$pid"
    mkdir -p "$dir"
    printf '%s\0' "$cmdline" > "$dir/cmdline"
    printf '%s\n' "$oom" > "$dir/oom_score_adj"
    # proc(5) stat: pid (comm) state ppid ... nice is field 19 overall,
    # i.e. field 17 after the "(comm) " prefix.
    # state ppid pgrp session tty tpgid flags minflt cminflt majflt cmajflt
    # utime stime cutime cstime priority nice ...
    local rest="S 1 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 $nice 1 0 0"
    printf '%s (%s) %s\n' "$pid" "$comm" "$rest" > "$dir/stat"
}

# Puts an executable stub on PATH that echoes $1 and records its args.
stub_command() {
    local name="$1" body="$2"
    mkdir -p "$SANDBOX/bin"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$SANDBOX/bin/$name"
    chmod +x "$SANDBOX/bin/$name"
    PATH="$SANDBOX/bin:$PATH"
    export PATH
}

# Sources chrome_colab_guard_v7.sh's function definitions only, pointed at
# the sandbox instead of the real kernel interfaces.
load_guard() {
    export CHROME_GUARD_LIB_ONLY=1
    export LOG_DIR="$SANDBOX/guardlog"
    export PROC_DIR="$SANDBOX/proc"
    export MEMINFO_FILE="$SANDBOX/meminfo"
    export MOUNTS_FILE="$SANDBOX/mounts"
    export TMPFS_TARGET="$SANDBOX/tmpfs-target"
    mkdir -p "$SANDBOX/proc"
    : > "$SANDBOX/meminfo"
    : > "$SANDBOX/mounts"
    # shellcheck disable=SC1091
    . "$REPO_ROOT/scripts/chrome_colab_guard_v7.sh"
    trap - EXIT
}

load_mido() {
    export MIDO_OPTIMIZE_LIB_ONLY=1
    export MIDO_OPTIMIZE_LOG="$SANDBOX/mido.log"
    # shellcheck disable=SC1091
    . "$REPO_ROOT/mido_optimize.sh"
}
