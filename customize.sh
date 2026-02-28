#!/system/bin/sh
# ADB Root - Magisk install-time customization script
# Validates device compatibility and preserves user configuration.

# --- Architecture check and binary selection ---
case "$ARCH" in
    arm64|arm|x86|x86_64) ;;
    *) abort "ERROR: Unsupported architecture: $ARCH" ;;
esac

ui_print "- Selecting adbd binary for $ARCH"
cp "$MODPATH/system/bin/adbd.$ARCH" "$MODPATH/system/bin/adbd"
chmod 755 "$MODPATH/system/bin/adbd"

# Clean up arch-suffixed binaries (not needed at runtime)
rm -f "$MODPATH/system/bin/adbd."*

# --- Android version check (API 28 = Android 9, API 29 = Android 10) ---
case "$API" in
    28) android_ver="Android 9 (Pie)" ;;
    29) android_ver="Android 10 (Q)" ;;
    *)
        case "$API" in
            27) android_ver="Android 8.1 (Oreo)" ;;
            30) android_ver="Android 11 (R)" ;;
            31) android_ver="Android 12 (S)" ;;
            32) android_ver="Android 12L" ;;
            33) android_ver="Android 13 (T)" ;;
            34) android_ver="Android 14 (U)" ;;
            35) android_ver="Android 15 (V)" ;;
            *)  android_ver="API $API" ;;
        esac
        abort "ERROR: ADB Root requires Android 9 or 10. Detected: $android_ver (API $API)"
        ;;
esac

ui_print "- Architecture: $ARCH"
ui_print "- Android version: $android_ver (API $API)"
ui_print "- Magisk version: $MAGISK_VER ($MAGISK_VER_CODE)"

# --- Preserve config and state from previous install ---
PREV_DIR="/data/adb/modules/adb_root"

if [ -f "$PREV_DIR/config.sh" ]; then
    ui_print "- Preserving existing config.sh"
    cp "$PREV_DIR/config.sh" "$MODPATH/config.sh"
else
    ui_print "- Installing default config.sh"
    cp "$MODPATH/common/default_config.sh" "$MODPATH/config.sh"
fi

if [ -f "$PREV_DIR/state.sh" ]; then
    ui_print "- Preserving existing state.sh"
    cp "$PREV_DIR/state.sh" "$MODPATH/state.sh"
fi

# --- Clean up files not needed at runtime ---
rm -rf "$MODPATH/common"

# --- Security warning ---
ui_print "************************************"
ui_print " WARNING: This module patches adbd"
ui_print " to always run as root and skips"
ui_print " USB authentication."
ui_print " "
ui_print " This weakens device security."
ui_print " Use only for debugging and"
ui_print " disable when not needed."
ui_print "************************************"
