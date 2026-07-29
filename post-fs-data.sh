#!/system/bin/sh
# mido-optimize Post-FS-Data Script
# Runs during boot (post-fs-data stage)
# This is where main optimization happens

MODDIR=${0%/*}
LOGFILE="/data/local/tmp/mido_optimize_magisk.log"

MIDO_LOG_FILE="$LOGFILE"
MIDO_LOG_TS_FMT="+[%H:%M:%S]"

# shellcheck source=scripts/lib/common.sh
if [ -r "$MODDIR/scripts/lib/common.sh" ]; then
    . "$MODDIR/scripts/lib/common.sh"
    # Lightweight Android version detection (baseline: Android 11 / API 30)
    log_android_version 30 "[post-fs-data]"
else
    echo "[post-fs-data] ERROR: missing $MODDIR/scripts/lib/common.sh" >> "$LOGFILE"
    exit 1
fi

# Execute optimization script
exec "$MODDIR/scripts/mido_optimize.sh" >> $LOGFILE 2>&1
