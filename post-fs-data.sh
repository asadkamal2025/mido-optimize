#!/system/bin/sh
# mido-optimize Post-FS-Data Script
# Runs during boot (post-fs-data stage)
# This is where main optimization happens

MODDIR=${0%/*}
LOGFILE="/data/local/tmp/mido_optimize_magisk.log"

# Lightweight Android version detection (baseline: Android 11 / API 30)
ANDROID_SDK="$(getprop ro.build.version.sdk 2>/dev/null)"
ANDROID_RELEASE="$(getprop ro.build.version.release 2>/dev/null)"
echo "[post-fs-data] Detected Android $ANDROID_RELEASE (API $ANDROID_SDK)" >> "$LOGFILE"

# Execute optimization script
exec "$MODDIR/scripts/mido_optimize.sh" >> $LOGFILE 2>&1