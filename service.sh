#!/system/bin/sh
# ADB Root - Magisk service script
# Ensures patched adbd is running as root after boot.
# If adbd fails to start, the module is auto-disabled for safety.

MODDIR=${0%/*}

log_msg() {
    /system/bin/log -t "adb_root" "$1"
}

# --- Auto-expiry: load config, track boots, enforce limit ---

# Default (overridden by config.sh)
MAX_BOOTS=10

# shellcheck source=/dev/null
[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"

# Load or initialize boot count
BOOT_COUNT=0
# shellcheck source=/dev/null
[ -f "$MODDIR/state.sh" ] && . "$MODDIR/state.sh"

BOOT_COUNT=$((BOOT_COUNT + 1))

# Write state atomically
printf 'BOOT_COUNT=%d\n' "$BOOT_COUNT" > "$MODDIR/state.sh.tmp"
mv "$MODDIR/state.sh.tmp" "$MODDIR/state.sh"

# Check boot-count expiry
if [ "$MAX_BOOTS" -gt 0 ] && [ "$BOOT_COUNT" -gt "$MAX_BOOTS" ]; then
    log_msg "Boot count $BOOT_COUNT exceeds limit $MAX_BOOTS, disabling module"
    touch "$MODDIR/disable"
    cmd notification post -S bigtext -t "ADB Root disabled" \
        "adb_root_expiry" "Boot limit reached ($BOOT_COUNT/$MAX_BOOTS). Re-enable manually and reset state.sh." 2>/dev/null
    exit 0
fi

# --- End auto-expiry ---

# Wait for adbd to appear (up to 30s)
i=0
while [ $i -lt 30 ]; do
    pidof adbd > /dev/null 2>&1 && break
    sleep 1
    i=$((i + 1))
done

# Check if adbd is already running as root
adbd_pid=$(pidof adbd)
if [ -n "$adbd_pid" ]; then
    adbd_uid=$(stat -c %u /proc/"$adbd_pid" 2>/dev/null)
    if [ "$adbd_uid" = "0" ]; then
        log_msg "adbd already running as root (pid $adbd_pid), nothing to do"
        exit 0
    fi
    log_msg "adbd running as non-root (uid $adbd_uid), restarting"
fi

# Kill existing adbd and start patched binary
killall adbd 2>/dev/null
sleep 1

# Start the patched adbd from our module
setprop service.adb.root 1
start adbd

# Verify adbd started (up to 10s)
i=0
while [ $i -lt 10 ]; do
    pidof adbd > /dev/null 2>&1 && break
    sleep 1
    i=$((i + 1))
done

if ! pidof adbd > /dev/null 2>&1; then
    log_msg "ERROR: adbd failed to start, disabling module"
    touch "$MODDIR/disable"
    # Try to restore adbd via init
    start adbd
fi
