#!/system/bin/sh
# ADB Root - Magisk service script
# Ensures patched adbd is running as root after boot.
# If adbd fails to start, the module is auto-disabled for safety.

MODDIR=${0%/*}

log_msg() {
    /system/bin/log -t "adb_root" "$1"
}

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
