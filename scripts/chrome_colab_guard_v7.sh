#!/system/bin/sh
# chrome_colab_guard_v7.sh
# Production Magisk service.d script for rooted mido (Redmi Note 4, SD625, 4GB RAM)
# Android 11 (LineageOS 18.1) + full GApps.
#
# Purpose:
#   - Optionally mount /data/local/tmp as tmpfs when it is safe (and KEEP checking
#     that it stays safe, not just once at boot)
#   - Protect Chrome's main process (and Colab tab session continuity) from
#     aggressive LMKD kills, WITHOUT blanket-shielding every renderer/child PID
#     and starving the rest of a 4GB device in the process
#   - Do all of the above with the minimum number of forked subprocesses per
#     loop tick, because on a 4GB SD625 device the guard script's own CPU/RAM
#     footprint competes directly with the thing it is trying to protect
#
# ─────────────────────────────────────────────────────────────────────────────
# CHANGE LOG vs v6 (Observe waste → Find hidden assumption → Break it → Gain)
# ─────────────────────────────────────────────────────────────────────────────
# 1) log() timestamp forking
#    Waste     : v6 forked `date` on EVERY log line. During a cold-start tick
#                touching N chrome PIDs that's 2N+ `date` forks in <1s.
#    Assumption: "each log line needs a freshly-forked timestamp."
#    Break     : Cache one timestamp per loop tick (LOOP_TS), refreshed once
#                at the top of the loop; log() reuses it.
#    Gain      : O(N) forks/tick -> O(1) forks/tick for logging.
#
# 2) list_chrome_pids() cmdline scanning
#    Waste     : v6 opened /proc/*/cmdline and forked `tr` PER candidate pid,
#                every 8-20s, forever.
#    Assumption: "matching a NUL-separated cmdline needs per-file decoding,"
#                and (a second, buried assumption in the fix attempt) "an
#                anchored regex like ^pkg$ will correctly match the whole
#                cmdline." Verified FALSE: /proc/pid/cmdline is NUL-
#                *terminated*, so `$` never lines up right after the package
#                name, and embedding a literal NUL into a shell-quoted ERE
#                is not reliably portable (confirmed broken across bash and
#                rejected by GNU grep in testing).
#    Break     : One `grep -laF` (fixed-string, unanchored) fork scans ALL
#                /proc/*/cmdline files as a cheap prefilter; exact
#                classification (main vs child vs "just a substring
#                lookalike, ignore it") is done with a shell `case` match on
#                the builtin-`read` cmdline string - zero extra forks and no
#                NUL/anchor edge cases.
#    Gain      : Enumeration cost drops from O(pids) forks to O(1) forks,
#                AND lookalike package names are no longer false-positived.
#
# 3) Reading proc values / nice field
#    Waste     : v6 forked `cat` to read oom_score_adj and forked `awk` to
#                read the naive `$19` field of /proc/pid/stat for "nice".
#    Assumption: "reading one short file needs an external process" AND
#                "comm (thread/process name) never contains a space or ')'".
#                The second assumption is FALSE (e.g. "GLThread 61"-style
#                names exist), which silently corrupts $19 field-splitting.
#    Break     : Use the shell builtin `read` (no fork) for oom_score_adj,
#                and parse /proc/pid/stat by splitting on the LAST "') '"
#                (proc(5)-correct even when comm has a space) - verified in
#                a throwaway shell before shipping this fix.
#    Gain      : 2 fewer forks per pid per tick AND a real correctness bug
#                fixed (silent mis-detection of "already correct" nice).
#
# 4) Blanket protection of every chrome-tagged PID
#    Waste     : v6 applied the SAME oom_score_adj=-300 / nice=-10 to the
#                main process, the GPU process, every sandboxed renderer,
#                and every background-tab renderer alike.
#    Assumption: "all chrome PIDs deserve equal, permanent protection."
#                This fights Android's own ActivityManager, which already
#                de-prioritizes invisible/background renderers on purpose so
#                LMKD can reclaim them cheaply. Force-shielding a background
#                tab's renderer with -300 does not save RAM - it just makes
#                LMKD kill something ELSE instead (possibly a more useful
#                app), which is the opposite of what a 4GB device needs.
#    Break     : Only the main browser process (cmdline == package name
#                exactly, no ":" suffix) gets strong protection. Renderer/
#                utility/GPU children get a much milder, capped adjustment
#                (enough to survive a brief memory blip during an active
#                Colab cell run) and are otherwise left to Android's normal
#                lifecycle so idle/background tabs can still be reclaimed.
#    Gain      : Fewer PIDs tracked (fewer forks overall), less RAM pinned,
#                no unfair collateral kills of unrelated apps.
#
# 5) One-shot tmpfs safety check
#    Waste     : v6 checked MemAvailable ONCE at boot, then left a 64MB
#                tmpfs mounted for the entire uptime no matter what happens
#                later (e.g. Chrome + a heavy Colab tab ballooning memory).
#    Assumption: "safe at boot" == "safe forever."
#    Break     : Periodically re-check MemAvailable while running; if it
#                drops under a critical floor, unmount tmpfs automatically
#                (best-effort, never blocks the guard loop).
#    Gain      : tmpfs can no longer become a self-inflicted OOM contributor.
#
# Install path:
#   /data/adb/service.d/chrome_colab_guard_v7.sh
# Permissions:
#   chmod 0755 /data/adb/service.d/chrome_colab_guard_v7.sh

# -----------------------------
# Config
# -----------------------------
CHROME_PKG="com.android.chrome"
LOG_DIR="/data/adb/chrome-colab-guard"
LOG_FILE="$LOG_DIR/chrome_colab_guard_v7.log"
STATE_DIR="$LOG_DIR/state"
LOCK_DIR="$LOG_DIR/lock"
PERSIST_PROP="persist.chrome.guard.enabled"
DEFAULT_ENABLED="1"
BOOT_WAIT_SECS=180
IDLE_SLEEP=20
ACTIVE_SLEEP=8

TMPFS_ENABLED="1"
TMPFS_TARGET="/data/local/tmp"
TMPFS_SIZE="64M"
# 4GB device with full GApps: be conservative. Require more headroom to
# mount, and keep re-checking so we can back out if things get tight later.
TMPFS_MIN_MEM_KB=524288      # 512MB free required to MOUNT
TMPFS_CRITICAL_MEM_KB=262144 # 256MB free triggers auto-UNMOUNT
TMPFS_RECHECK_EVERY=15       # re-validate tmpfs safety every N loop ticks

# Main browser process: strong protection (it coordinates every tab; losing
# it loses the whole session, including an in-progress Colab connection).
MAIN_OOM_SCORE="-300"
MAIN_NICE_LEVEL="-10"

# Renderer/GPU/utility children: mild, capped protection only. Enough to
# survive a short memory spike, not enough to defeat Android's normal
# background-tab reclaim (which is what actually saves RAM on 4GB).
CHILD_OOM_SCORE="-100"
CHILD_NICE_LEVEL="0"

PRUNE_EVERY=5   # only scan STATE_DIR for stale entries every N ticks

umask 022
PATH=/system/bin:/system/xbin:/sbin:/vendor/bin:$PATH

mkdir -p "$LOG_DIR" "$STATE_DIR" 2>/dev/null

# Cached per-tick timestamp - refreshed once per loop iteration by
# refresh_tick_ts(). log() reuses it instead of forking `date` every line.
LOOP_TS=""

refresh_tick_ts() {
    LOOP_TS="$(date '+%F %T')"
}

log() {
    echo "$LOOP_TS  $*" >> "$LOG_FILE"
}

prop_get() {
    getprop "$1" 2>/dev/null
}

prop_enabled() {
    current="$(prop_get "$PERSIST_PROP")"
    [ -z "$current" ] && current="$DEFAULT_ENABLED"
    [ "$current" = "1" ]
}

cleanup() {
    rm -rf "$LOCK_DIR" 2>/dev/null
    refresh_tick_ts
    log "[STOP] exiting"
}
trap cleanup INT TERM EXIT

acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
        return 0
    fi

    old_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
    if [ -n "$old_pid" ] && [ -d "/proc/$old_pid" ]; then
        log "[SKIP] already running with PID=$old_pid"
        exit 0
    fi

    rm -rf "$LOCK_DIR" 2>/dev/null
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
        return 0
    fi

    log "[FAIL] could not acquire lock"
    exit 1
}

wait_for_boot() {
    elapsed=0
    while [ "$elapsed" -lt "$BOOT_WAIT_SECS" ]; do
        if [ "$(prop_get sys.boot_completed)" = "1" ] && [ -d /proc/1 ]; then
            refresh_tick_ts
            log "[OK] boot completed after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    refresh_tick_ts
    log "[WARN] boot wait timeout reached; continuing anyway"
    return 0
}

get_mem_available_kb() {
    awk '/MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null
}

is_tmpfs_mounted() {
    awk -v target="$TMPFS_TARGET" '$2 == target && $3 == "tmpfs" {found=1} END{exit(found?0:1)}' /proc/mounts
}

mount_tmpfs_if_needed() {
    [ "$TMPFS_ENABLED" = "1" ] || {
        log "[SKIP] tmpfs disabled by config"
        return 0
    }

    if is_tmpfs_mounted; then
        log "[SKIP] $TMPFS_TARGET already tmpfs"
        return 0
    fi

    avail_kb="$(get_mem_available_kb)"
    case "$avail_kb" in
        ''|*[!0-9]*)
            log "[WARN] MemAvailable unreadable; skip tmpfs mount"
            return 0
            ;;
    esac

    if [ "$avail_kb" -lt "$TMPFS_MIN_MEM_KB" ]; then
        log "[SKIP] MemAvailable=${avail_kb}KB < ${TMPFS_MIN_MEM_KB}KB; tmpfs not mounted"
        return 0
    fi

    mkdir -p "$TMPFS_TARGET" 2>/dev/null
    if mount -t tmpfs -o "size=$TMPFS_SIZE,mode=1777,nosuid,nodev" tmpfs "$TMPFS_TARGET" 2>/dev/null; then
        log "[OK] mounted tmpfs on $TMPFS_TARGET size=$TMPFS_SIZE (avail=${avail_kb}KB)"
    else
        log "[FAIL] tmpfs mount failed on $TMPFS_TARGET"
    fi
}

# v7: tmpfs is no longer "mount once, trust forever". A 4GB device running
# Chrome + a Colab tab can burn through hundreds of MB in minutes, so we
# keep re-validating and back out if memory gets critically low.
recheck_tmpfs_safety() {
    [ "$TMPFS_ENABLED" = "1" ] || return 0
    is_tmpfs_mounted || return 0

    avail_kb="$(get_mem_available_kb)"
    case "$avail_kb" in
        ''|*[!0-9]*) return 0 ;;
    esac

    if [ "$avail_kb" -lt "$TMPFS_CRITICAL_MEM_KB" ]; then
        log "[WARN] MemAvailable=${avail_kb}KB critical; unmounting tmpfs on $TMPFS_TARGET"
        umount "$TMPFS_TARGET" 2>/dev/null \
            && log "[OK] tmpfs unmounted from $TMPFS_TARGET" \
            || log "[FAIL] tmpfs unmount failed (likely busy); will retry next check"
    fi
}

# v7: single-fork enumeration instead of one `tr` fork per candidate pid.
#
# NOTE on a subtlety we deliberately test for: /proc/pid/cmdline is
# NUL-separated AND NUL-terminated. That means an anchored regex like
# `^pkg$` never matches (the byte right after "pkg" is \0, not end-of-line
# to grep), and embedding a literal NUL byte into a shell-quoted ERE is not
# reliably portable across shells/grep builds (verified: it silently breaks
# in bash and is rejected outright by GNU grep here). So we deliberately do
# NOT try to anchor inside the regex.
#
# Instead: `grep -laF` does a single, portable, unanchored FIXED-STRING
# prefilter across every /proc/*/cmdline in ONE forked process (no NUL/regex
# edge cases - substring search on raw bytes works fine and is verified).
# Anything that merely contains the package name as a substring (e.g. a
# hypothetical "com.android.chrome2") is still just a *candidate* at this
# point - exact classification into main vs child happens next via a shell
# `case` match against the fully-read cmdline string, which correctly
# rejects lookalike package names and separates main process from
# renderer/GPU/utility children with zero extra forks.
MAIN_PIDS=""
CHILD_PIDS=""

collect_chrome_pids() {
    MAIN_PIDS=""
    CHILD_PIDS=""

    matches="$(grep -laF "$CHROME_PKG" /proc/[0-9]*/cmdline 2>/dev/null)"
    [ -n "$matches" ] || return 0

    for f in $matches; do
        pid="${f#/proc/}"
        pid="${pid%/cmdline}"
        # Re-read just this one match to classify exactly (builtin `read`,
        # no extra process forked).
        IFS= read -r cmd < "$f" 2>/dev/null
        case "$cmd" in
            "$CHROME_PKG")
                MAIN_PIDS="$MAIN_PIDS $pid"
                ;;
            "$CHROME_PKG":*)
                CHILD_PIDS="$CHILD_PIDS $pid"
                ;;
            *)
                # Substring-only match (e.g. lookalike package name) -
                # not actually our target, ignore it.
                ;;
        esac
    done
}

# v7: no `cat` fork - shell builtin `read` reads the file directly.
read_proc_value() {
    file="$1"
    [ -r "$file" ] || return 1
    IFS= read -r _val < "$file" 2>/dev/null || return 1
    echo "$_val"
}

# v7: no `awk` fork and no fragile "$19 by raw whitespace" assumption.
# comm (field 2) is the only field that can contain spaces/parens, and it is
# always wrapped in "(...)"; splitting on the LAST "') '" is correct per
# proc(5) regardless of what's inside the parens. After that split, `nice`
# is relative field 17 (state=1 ... nice=17 of the remainder).
read_proc_nice() {
    pid="$1"
    stat_line="$(read_proc_value "/proc/$pid/stat")" || return 1
    rest="${stat_line##*) }"
    set -- $rest
    [ "$#" -ge 17 ] || return 1
    echo "${17}"
}

apply_pid_tuning() {
    pid="$1"
    oom_score="$2"
    nice_level="$3"
    [ -d "/proc/$pid" ] || return 1

    changed=0

    current_oom="$(read_proc_value "/proc/$pid/oom_score_adj")"
    if [ "$current_oom" != "$oom_score" ]; then
        if echo "$oom_score" > "/proc/$pid/oom_score_adj" 2>/dev/null; then
            changed=1
            log "[OK] pid=$pid oom_score_adj -> $oom_score"
        else
            log "[WARN] pid=$pid oom_score_adj write failed"
        fi
    fi

    current_nice="$(read_proc_nice "$pid")"
    if [ "$current_nice" != "$nice_level" ]; then
        if renice "$nice_level" -p "$pid" >/dev/null 2>&1; then
            changed=1
            log "[OK] pid=$pid nice -> $nice_level"
        else
            log "[WARN] pid=$pid renice failed"
        fi
    fi

    [ "$changed" = "1" ] || return 2
    return 0
}

# Only re-tune a pid whose state file is missing or whose values drifted -
# avoids redundant writes/renice calls on every tick for pids we already
# fixed. State files are tagged with which tier (main/child) so a pid that
# somehow changes classification (shouldn't happen, but PIDs get reused)
# is re-evaluated instead of trusting a stale tag forever.
tune_if_needed() {
    pid="$1"
    tier="$2"
    oom_score="$3"
    nice_level="$4"
    state_file="$STATE_DIR/$pid"
    tag="${tier}:${oom_score}:${nice_level}"

    if [ ! -f "$state_file" ] || [ "$(cat "$state_file" 2>/dev/null)" != "$tag" ]; then
        apply_pid_tuning "$pid" "$oom_score" "$nice_level"
        echo "$tag" > "$state_file"
        return 0
    fi

    current_oom="$(read_proc_value "/proc/$pid/oom_score_adj")"
    current_nice="$(read_proc_nice "$pid")"
    if [ "$current_oom" != "$oom_score" ] || [ "$current_nice" != "$nice_level" ]; then
        apply_pid_tuning "$pid" "$oom_score" "$nice_level"
    fi
}

prune_stale_state() {
    for f in "$STATE_DIR"/*; do
        [ -e "$f" ] || break
        pid="${f##*/}"
        [ -d "/proc/$pid" ] || rm -f "$f" 2>/dev/null
    done
}

main_loop() {
    tick=0
    while true; do
        tick=$((tick + 1))
        refresh_tick_ts

        if ! prop_enabled; then
            log "[SKIP] disabled via $PERSIST_PROP"
            sleep "$IDLE_SLEEP"
            continue
        fi

        collect_chrome_pids
        found=0

        for pid in $MAIN_PIDS; do
            found=1
            tune_if_needed "$pid" "main" "$MAIN_OOM_SCORE" "$MAIN_NICE_LEVEL"
        done

        for pid in $CHILD_PIDS; do
            found=1
            tune_if_needed "$pid" "child" "$CHILD_OOM_SCORE" "$CHILD_NICE_LEVEL"
        done

        if [ $((tick % PRUNE_EVERY)) -eq 0 ]; then
            prune_stale_state
        fi

        if [ $((tick % TMPFS_RECHECK_EVERY)) -eq 0 ]; then
            recheck_tmpfs_safety
        fi

        if [ "$found" = "1" ]; then
            sleep "$ACTIVE_SLEEP"
        else
            sleep "$IDLE_SLEEP"
        fi
    done
}

acquire_lock
refresh_tick_ts
log "===== Chrome Colab Guard V7 Started ====="
wait_for_boot
mount_tmpfs_if_needed
main_loop
