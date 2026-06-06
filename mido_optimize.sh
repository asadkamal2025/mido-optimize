#!/system/bin/sh
# mido (Redmi Note 4 SD625) Extreme DeGoogle + Balanced Perf Script v1.1
# Android 11 LineageOS/Havoc - Magisk/KSU compatible

LOGFILE="/data/local/tmp/mido_optimize.log"
echo "=== mido Optimize v1.1 Start: $(date) ===" > $LOGFILE

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a $LOGFILE
}

check_node() {
    if [ -e "$1" ] || [ -f "$1" ]; then
        return 0
    else
        log "SKIP: $1 not present"
        return 1
    fi
}

log "DeGoogle: Safe package disables"
PACKAGES_TO_DISABLE="
com.google.android.gms
com.google.android.gsf
com.google.android.googlequicksearchbox
com.google.android.partnersetup
com.google.android.feedback
com.google.android.printservice
com.google.android.syncadapters.contacts
com.google.android.syncadapters.calendar
"
for pkg in $PACKAGES_TO_DISABLE; do
    if pm list packages 2>/dev/null | grep -q "$pkg"; then
        pm disable-user --user 0 "$pkg" 2>/dev/null && log "Disabled: $pkg" || log "Already disabled or failed: $pkg"
    fi
done

setprop ro.gsm.imei "000000000000000" 2>/dev/null || true
setprop persist.sys.gps.gps_lock 0 2>/dev/null || true
setprop gsm.sim.operator.alpha "" 2>/dev/null || true
log "DeGoogle done"

log "LMKD + VM for 3/4GB RAM"
check_node /sys/module/lowmemorykiller/parameters/psi_enabled && echo 1 > $_ && log "PSI enabled"
setprop ro.lmk.use_psi true
setprop ro.lmk.low_ram true
setprop ro.lmk.kill_heaviest_task 0
setprop ro.lmk.kill_timeout_ms 1500
echo 90 > /proc/sys/vm/vfs_cache_pressure
echo 60 > /proc/sys/vm/swappiness
echo 1 > /proc/sys/vm/watermark_boost_factor 2>/dev/null || true
log "Memory tuning applied"

log "CPU Interactive tuning"
GOV_PATH="/sys/devices/system/cpu/cpufreq/interactive"
CPU_GOV="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
check_node "$CPU_GOV" && echo "interactive" > "$CPU_GOV" && log "Interactive governor set"
check_node "$GOV_PATH/above_hispeed_delay" && echo "19000 1382400:49000 1804800:19000" > "$_"
check_node "$GOV_PATH/go_hispeed_load" && echo 85 > "$_"
check_node "$GOV_PATH/hispeed_freq" && echo 1382400 > "$_"
check_node "$GOV_PATH/target_loads" && echo "80 960000:65 1382400:75 1804800:90" > "$_"
check_node "$GOV_PATH/boost" && echo 1 > "$_"
check_node "$GOV_PATH/use_sched_load" && echo 1 > "$_"
log "CPU tuning done"

log "GPU tuning"
GPU_BASE="/sys/class/kgsl/kgsl-3d0"
check_node "$GPU_BASE/devfreq/governor" && echo "simple_ondemand" > "$_" 2>/dev/null || true && log "simple_ondemand GPU governor"
check_node "$GPU_BASE/max_pwrlevel" && echo 0 > "$_" 2>/dev/null || true
check_node "$GPU_BASE/throttling" && echo 1 > "$_" 2>/dev/null || true
log "GPU conditional tuning done"

log "Logging + I/O reduction"
setprop persist.logd.logpersistd stop 2>/dev/null || true
setprop log.tag.stats_log I 2>/dev/null || true
setprop persist.vendor.radio.adb_log_on 0 2>/dev/null || true
log "=== mido Optimize v1.1 Complete: $(date) ==="