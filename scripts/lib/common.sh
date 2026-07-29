#!/system/bin/sh
# common.sh - shared helpers for the mido-optimize shell scripts.
#
# POSIX sh only (Android /system/bin/sh is mksh) - no bashisms.
# Source it, never execute it:
#
#     . "$(dirname "$0")/lib/common.sh"
#
# Logging is configured by the sourcing script through these variables:
#   MIDO_LOG_FILE      path of the log file                (default below)
#   MIDO_LOG_TS_FMT    `date` format used for timestamps
#   MIDO_LOG_TEE       1 -> also echo to stdout            (default 0)
#   MIDO_LOG_CACHE_TS  1 -> reuse the timestamp refreshed by
#                      refresh_log_ts() instead of forking `date` per line

MIDO_LOG_FILE="${MIDO_LOG_FILE:-/data/local/tmp/mido_optimize.log}"
MIDO_LOG_TS_FMT="${MIDO_LOG_TS_FMT:-+%H:%M:%S}"
MIDO_LOG_TEE="${MIDO_LOG_TEE:-0}"
MIDO_LOG_CACHE_TS="${MIDO_LOG_CACHE_TS:-0}"
MIDO_LOG_TS=""

refresh_log_ts() {
    MIDO_LOG_TS="$(date "$MIDO_LOG_TS_FMT")"
}

log() {
    [ "$MIDO_LOG_CACHE_TS" = "1" ] || refresh_log_ts
    if [ "$MIDO_LOG_TEE" = "1" ]; then
        echo "$MIDO_LOG_TS $*" | tee -a "$MIDO_LOG_FILE"
    else
        echo "$MIDO_LOG_TS $*" >> "$MIDO_LOG_FILE"
    fi
}

require_root() {
    [ "$(id -u)" = "0" ] && return 0
    log "ERROR: Must run as root (su). Exiting."
    exit 1
}

# True when the kernel/sysfs node exists (files and device nodes alike).
check_node() {
    if [ -e "$1" ]; then
        return 0
    fi
    log "SKIP: $1 not present"
    return 1
}

# write_node <node> <value> [label]
# The check-write-log triple that every tuning block needs; logs
# "<label> OK" on success so callers keep their existing log wording.
write_node() {
    node="$1"
    value="$2"
    label="${3:-$node=$value}"

    check_node "$node" || return 1
    if echo "$value" > "$node" 2>/dev/null; then
        log "$label OK"
        return 0
    fi
    log "WARN: failed writing $value to $node"
    return 1
}

# log_android_version [min_api] [prefix]
# Logs the detected Android release/API level and warns when it is below the
# supported baseline. Never exits, so unsupported ROMs still run.
log_android_version() {
    min_api="${1:-30}"
    prefix="$2"
    [ -n "$prefix" ] && prefix="$prefix "
    android_sdk="$(getprop ro.build.version.sdk 2>/dev/null)"
    android_release="$(getprop ro.build.version.release 2>/dev/null)"

    log "${prefix}Detected Android $android_release (API $android_sdk)"
    if [ -n "$android_sdk" ] && [ "$android_sdk" -lt "$min_api" ] 2>/dev/null; then
        log "${prefix}WARNING: Android $android_release (API $android_sdk) is below supported baseline (API $min_api)."
    fi
}

# set_prop <name> <value> - setprop never aborts the script.
set_prop() {
    setprop "$1" "$2" 2>/dev/null || true
}

# Read a single line from a file with the shell builtin (no `cat` fork).
read_proc_value() {
    file="$1"
    [ -r "$file" ] || return 1
    IFS= read -r _val < "$file" 2>/dev/null || return 1
    echo "$_val"
}

is_positive_int() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

get_mem_available_kb() {
    awk '/MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null
}

is_tmpfs_mounted() {
    awk -v target="$1" '$2 == target && $3 == "tmpfs" {found=1} END{exit(found?0:1)}' \
        /proc/mounts 2>/dev/null
}

# mount_tmpfs <target> <size> [mount options]
# No-op (success) when the target already carries a tmpfs.
mount_tmpfs() {
    target="$1"
    size="$2"
    opts="${3:-mode=1777,nosuid,nodev}"

    if is_tmpfs_mounted "$target"; then
        log "SKIP: $target already tmpfs"
        return 0
    fi

    mkdir -p "$target" 2>/dev/null
    if mount -t tmpfs -o "size=$size,$opts" tmpfs "$target" 2>/dev/null; then
        log "tmpfs mounted on $target size=$size OK"
        return 0
    fi
    log "WARN: tmpfs mount failed on $target"
    return 1
}
