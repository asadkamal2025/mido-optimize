#!/system/bin/sh
# Convenience entry point kept at the repository/module root.
# The implementation lives in scripts/mido_optimize.sh so there is a single
# copy to maintain (this file used to be a byte-for-byte duplicate of it).

ROOT_DIR="${0%/*}"
[ "$ROOT_DIR" = "$0" ] && ROOT_DIR="."

exec "$ROOT_DIR/scripts/mido_optimize.sh" "$@"
