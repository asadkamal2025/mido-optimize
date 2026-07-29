#!/system/bin/sh
# mido-optimize Post-FS-Data Script
# Runs during boot (post-fs-data stage)
# This is where main optimization happens

MODDIR=${0%/*}
# Root-only log location: /data/local/tmp is world-writable, so a log written
# there as root can be hijacked via a pre-planted symlink.
LOGDIR="/data/adb/mido-optimize"
LOGFILE="$LOGDIR/mido_optimize_magisk.log"
mkdir -p "$LOGDIR" 2>/dev/null
chmod 0700 "$LOGDIR" 2>/dev/null
[ -L "$LOGFILE" ] && rm -f "$LOGFILE"

# Execute optimization script
exec "$MODDIR/scripts/mido_optimize.sh" >> "$LOGFILE" 2>&1