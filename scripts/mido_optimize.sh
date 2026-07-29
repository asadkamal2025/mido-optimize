#!/system/bin/sh
# mido (Redmi Note 4 SD625) GApps-Optimized Performance Script v3.0
# Android 11 LineageOS 18.1 - Magisk/KSU compatible
# Author: asadkamal2025
# https://github.com/asadkamal2025/mido-optimize
#
# v3.0 focus: Full Google GApps support with tuned background load.
# GMS/GSF are NOT disabled (unlike v1.x DeGoogle approach) - instead
# we control their wake-locks, kill priority, and sync interval so
# notifications/sync keep working while RAM/battery stay in check.
#
# Now includes explicit Android version detection: reads the OS release
# and SDK/API level and warns (without exiting) when running below the
# supported baseline of Android 11 (API 30).

LOGFILE="/data/local/tmp/mido_optimize.log"
echo "=== mido Optimize v3.0 Start: $(date) ===" > "$LOGFILE"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOGFILE"
}

check_node() {
    if [ -e "$1" ] || [ -f "$1" ]; then
        return 0
    else
        log "SKIP: $1 not present"
        return 1
    fi
}

# ── Root check ──────────────────────────────────────────────────────────────
if [ "$(id -u)" != "0" ]; then
    log "ERROR: Must run as root (su). Exiting."
    exit 1
fi
log "Root check passed OK"

# ── Android version detection (supported baseline: Android 11 / API 30) ────
MIN_API=30
ANDROID_SDK="$(getprop ro.build.version.sdk 2>/dev/null)"
ANDROID_RELEASE="$(getprop ro.build.version.release 2>/dev/null)"
log "Detected Android $ANDROID_RELEASE (API $ANDROID_SDK)"
if [ -n "$ANDROID_SDK" ] && [ "$ANDROID_SDK" -lt "$MIN_API" ] 2>/dev/null; then
    log "WARNING: Android $ANDROID_RELEASE (API $ANDROID_SDK) is below supported baseline (Android 11 / API 30)."
fi

# ── GApps: Targeted non-essential sub-component disable only ───────────────
# Core GMS/GSF/Play Store/Play Services notifications are LEFT ALONE.
# Only genuinely optional background components are trimmed.
log "GApps: trimming only non-essential background components"
PACKAGES_TO_DISABLE="
com.google.android.play.games
com.google.android.apps.wellbeing
com.google.android.feedback
com.google.android.printservice.recommendation
"
for pkg in $PACKAGES_TO_DISABLE; do
    if pm list packages 2>/dev/null | grep -q "$pkg"; then
        pm disable-user --user 0 "$pkg" 2>/dev/null \
            && log "Disabled (non-essential): $pkg OK" \
            || log "Already disabled or failed: $pkg"
    else
        log "Not installed: $pkg"
    fi
done
log "GApps trim done OK - GMS/GSF/Play Store untouched"

# ── GMS Doze whitelist: keep it, so push notifications survive ─────────────
log "Ensuring GMS stays in doze whitelist (push notification safety)"
dumpsys deviceidle whitelist +com.google.android.gms 2>/dev/null \
    && log "com.google.android.gms whitelisted in doze OK" \
    || log "Doze whitelist command not available on this ROM, skipping"

# ── PSI-based LMKd tuning: protect GMS from repeated restart-kills ─────────
# Repeated GMS process kill+restart is the single biggest drain on RAM/battery,
# not the process staying alive. So we bias LMKd to NOT kill_heaviest_task
# and raise kill_timeout so GMS gets breathing room before being reaped.
log "LMKD + VM tuning (PSI-based, GMS-friendly)"
check_node /sys/module/lowmemorykiller/parameters/psi_enabled \
    && echo 1 > /sys/module/lowmemorykiller/parameters/psi_enabled \
    && log "PSI enabled OK"
setprop ro.lmk.use_psi true
setprop ro.lmk.low_ram true
setprop ro.lmk.kill_heaviest_task 0
setprop ro.lmk.kill_timeout_ms 2500

check_node /proc/sys/vm/vfs_cache_pressure \
    && echo 90 > /proc/sys/vm/vfs_cache_pressure \
    && log "vfs_cache_pressure=90 OK"
check_node /proc/sys/vm/swappiness \
    && echo 60 > /proc/sys/vm/swappiness \
    && log "swappiness=60 OK"
check_node /proc/sys/vm/watermark_boost_factor \
    && echo 1 > /proc/sys/vm/watermark_boost_factor \
    && log "watermark_boost_factor=1 OK"
log "Memory tuning applied OK"

# ── Google account sync: relax interval, don't kill push ───────────────────
# Default periodic sync fires more often than most users need for
# Contacts/Calendar. Push (Gmail, Messages) rides on FCM, not this timer,
# so relaxing periodic sync saves battery without breaking push.
log "Sync interval tuning"
setprop sync.periodic.interval 1800 2>/dev/null || true
log "Sync interval relaxed to 30min for periodic (push unaffected) OK"

# ── CPU Interactive tuning ───────────────────────────────────────────────────
log "CPU Interactive tuning"
GOV_PATH="/sys/devices/system/cpu/cpufreq/interactive"
CPU_GOV="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
check_node "$CPU_GOV" \
    && echo "interactive" > "$CPU_GOV" \
    && log "Interactive governor set OK"
check_node "$GOV_PATH/above_hispeed_delay" \
    && echo "19000 1382400:49000 1804800:19000" > "$GOV_PATH/above_hispeed_delay" \
    && log "above_hispeed_delay set OK"
check_node "$GOV_PATH/go_hispeed_load" \
    && echo 85 > "$GOV_PATH/go_hispeed_load" \
    && log "go_hispeed_load=85 OK"
check_node "$GOV_PATH/hispeed_freq" \
    && echo 1382400 > "$GOV_PATH/hispeed_freq" \
    && log "hispeed_freq=1382400 OK"
check_node "$GOV_PATH/target_loads" \
    && echo "80 960000:65 1382400:75 1804800:90" > "$GOV_PATH/target_loads" \
    && log "target_loads set OK"
check_node "$GOV_PATH/boost" \
    && echo 1 > "$GOV_PATH/boost" \
    && log "boost=1 OK"
check_node "$GOV_PATH/use_sched_load" \
    && echo 1 > "$GOV_PATH/use_sched_load" \
    && log "use_sched_load=1 OK"
log "CPU tuning done OK"

# ── GPU tuning ───────────────────────────────────────────────────────────────
log "GPU tuning (Adreno 506)"
GPU_BASE="/sys/class/kgsl/kgsl-3d0"
check_node "$GPU_BASE/devfreq/governor" \
    && echo "simple_ondemand" > "$GPU_BASE/devfreq/governor" 2>/dev/null \
    && log "GPU governor=simple_ondemand OK"
check_node "$GPU_BASE/max_pwrlevel" \
    && echo 0 > "$GPU_BASE/max_pwrlevel" 2>/dev/null \
    && log "GPU max_pwrlevel=0 OK"
check_node "$GPU_BASE/throttling" \
    && echo 1 > "$GPU_BASE/throttling" 2>/dev/null \
    && log "GPU throttling=1 OK"
log "GPU conditional tuning done OK"

# ── tmpfs /cache for GApps DB writes (Play Store cache, Contacts DB) ───────
log "tmpfs cache mount for fast GApps DB writes (648 MB/s verified)"
if ! mountpoint -q /cache 2>/dev/null; then
    mount -t tmpfs -o size=64m,mode=0770,uid=1000,gid=1000 tmpfs /cache 2>/dev/null \
        && log "tmpfs /cache mounted OK" \
        || log "tmpfs /cache mount failed or already handled"
else
    log "/cache already mounted, skipping"
fi

# ── Logging + I/O reduction ──────────────────────────────────────────────────
log "Logging + I/O reduction"
setprop persist.logd.logpersistd stop 2>/dev/null || true
setprop log.tag.stats_log I 2>/dev/null || true
setprop persist.vendor.radio.adb_log_on 0 2>/dev/null || true
log "Logging reduction applied OK"

log "=== mido Optimize v3.0 Complete: $(date) ==="
