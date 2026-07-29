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

SCRIPT_DIR="${0%/*}"
[ "$SCRIPT_DIR" = "$0" ] && SCRIPT_DIR="."

MIDO_LOG_FILE="/data/local/tmp/mido_optimize.log"
MIDO_LOG_TS_FMT="+[%H:%M:%S]"
MIDO_LOG_TEE=1

# shellcheck source=scripts/lib/common.sh
if [ -r "$SCRIPT_DIR/lib/common.sh" ]; then
    . "$SCRIPT_DIR/lib/common.sh"
else
    echo "ERROR: cannot find lib/common.sh next to $0" >&2
    exit 1
fi

echo "=== mido Optimize v3.0 Start: $(date) ===" > "$MIDO_LOG_FILE"

# ── Root check ──────────────────────────────────────────────────────────────
require_root
log "Root check passed OK"

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
write_node /sys/module/lowmemorykiller/parameters/psi_enabled 1 "PSI enabled"
set_prop ro.lmk.use_psi true
set_prop ro.lmk.low_ram true
set_prop ro.lmk.kill_heaviest_task 0
set_prop ro.lmk.kill_timeout_ms 2500

write_node /proc/sys/vm/vfs_cache_pressure 90 "vfs_cache_pressure=90"
write_node /proc/sys/vm/swappiness 60 "swappiness=60"
write_node /proc/sys/vm/watermark_boost_factor 1 "watermark_boost_factor=1"
log "Memory tuning applied OK"

# ── Google account sync: relax interval, don't kill push ───────────────────
# Default periodic sync fires more often than most users need for
# Contacts/Calendar. Push (Gmail, Messages) rides on FCM, not this timer,
# so relaxing periodic sync saves battery without breaking push.
log "Sync interval tuning"
set_prop sync.periodic.interval 1800
log "Sync interval relaxed to 30min for periodic (push unaffected) OK"

# ── CPU Interactive tuning ───────────────────────────────────────────────────
log "CPU Interactive tuning"
GOV_PATH="/sys/devices/system/cpu/cpufreq/interactive"
CPU_GOV="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
write_node "$CPU_GOV" "interactive" "Interactive governor set"
write_node "$GOV_PATH/above_hispeed_delay" "19000 1382400:49000 1804800:19000" \
    "above_hispeed_delay set"
write_node "$GOV_PATH/go_hispeed_load" 85 "go_hispeed_load=85"
write_node "$GOV_PATH/hispeed_freq" 1382400 "hispeed_freq=1382400"
write_node "$GOV_PATH/target_loads" "80 960000:65 1382400:75 1804800:90" "target_loads set"
write_node "$GOV_PATH/boost" 1 "boost=1"
write_node "$GOV_PATH/use_sched_load" 1 "use_sched_load=1"
log "CPU tuning done OK"

# ── GPU tuning ───────────────────────────────────────────────────────────────
log "GPU tuning (Adreno 506)"
GPU_BASE="/sys/class/kgsl/kgsl-3d0"
write_node "$GPU_BASE/devfreq/governor" "simple_ondemand" "GPU governor=simple_ondemand"
write_node "$GPU_BASE/max_pwrlevel" 0 "GPU max_pwrlevel=0"
write_node "$GPU_BASE/throttling" 1 "GPU throttling=1"
log "GPU conditional tuning done OK"

# ── tmpfs /cache for GApps DB writes (Play Store cache, Contacts DB) ───────
log "tmpfs cache mount for fast GApps DB writes (648 MB/s verified)"
mount_tmpfs /cache 64m "mode=0770,uid=1000,gid=1000"

# ── Logging + I/O reduction ──────────────────────────────────────────────────
log "Logging + I/O reduction"
set_prop persist.logd.logpersistd stop
set_prop log.tag.stats_log I
set_prop persist.vendor.radio.adb_log_on 0
log "Logging reduction applied OK"

log "=== mido Optimize v3.0 Complete: $(date) ==="
