#!/system/bin/sh

# Reset adb root property
if command -v resetprop >/dev/null 2>&1; then
    resetprop --delete service.adb.root
fi

# Restart adbd to pick up stock binary
killall adbd 2>/dev/null
start adbd
