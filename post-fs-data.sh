#!/system/bin/sh
# mido-optimize Post-FS-Data Script
# Runs during boot (post-fs-data stage)
# This is where main optimization happens

MODDIR=${0%/*}
LOGFILE="/data/local/tmp/mido_optimize_magisk.log"
SCRIPT="$MODDIR/scripts/mido_optimize.sh"

if ! : >> "$LOGFILE" 2>/dev/null; then
    echo "mido-optimize: cannot write $LOGFILE" >&2
    LOGFILE="/dev/null"
fi

# Lightweight Android version detection (baseline: Android 11 / API 30)
ANDROID_SDK="$(getprop ro.build.version.sdk 2>/dev/null)"
ANDROID_RELEASE="$(getprop ro.build.version.release 2>/dev/null)"
if [ -z "$ANDROID_SDK" ]; then
    echo "[post-fs-data] WARN: could not read ro.build.version.sdk" >> "$LOGFILE"
else
    echo "[post-fs-data] Detected Android $ANDROID_RELEASE (API $ANDROID_SDK)" >> "$LOGFILE"
fi

if [ ! -r "$SCRIPT" ]; then
    echo "mido-optimize: optimization script missing at $SCRIPT" | tee -a "$LOGFILE" >&2
    exit 1
fi

# Run (rather than exec) so a failing optimization run is logged and its exit
# status is propagated to the caller instead of disappearing.
sh "$SCRIPT" >> "$LOGFILE" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
    echo "mido-optimize: $SCRIPT exited with status $status" >> "$LOGFILE"
fi
exit "$status"
