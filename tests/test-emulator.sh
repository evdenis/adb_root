#!/usr/bin/env bash
#
# End-to-end emulator test for the adb_root Magisk module.
#
# Boots an Android 10 (API 29) x86_64 emulator, roots it with Magisk via
# rootAVD, installs the module, and verifies it works.
#
# Requirements:
#   - Android SDK tools: emulator, sdkmanager, avdmanager, adb
#   - KVM (/dev/kvm)
#   - Internet (first run: downloads rootAVD + Magisk APK)
#
# Usage: ./tests/test-emulator.sh
#

set -euo pipefail

# --- Configuration ---
AVD_NAME="adb_root_test"
SYSTEM_IMAGE="system-images;android-29;google_apis;x86_64"
SYSTEM_IMAGE_PATH="system-images/android-29/google_apis/x86_64"
BOOT_TIMEOUT=120
ROOTAVD_DIR=".cache/rootAVD"
ROOTAVD_REPO="https://gitlab.com/newbit/rootAVD.git"

# Resolve project root (one level up from tests/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# --- Pass/fail counters (same pattern as test-adbd-binary.sh) ---
PASS=0
FAIL=0
EMULATOR_PID=""

pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

cleanup() {
    if [[ -n "$EMULATOR_PID" ]] && kill -0 "$EMULATOR_PID" 2>/dev/null; then
        echo "Cleaning up: killing emulator (pid $EMULATOR_PID)"
        kill "$EMULATOR_PID" 2>/dev/null || true
        wait "$EMULATOR_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# --- Prerequisites check ---
echo "=== Prerequisites ==="

MISSING=""
for cmd in emulator sdkmanager avdmanager adb; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING="$MISSING $cmd"
    fi
done

if [[ -n "$MISSING" ]]; then
    echo "ERROR: missing required commands:$MISSING"
    echo "Install the Android SDK and ensure these are on PATH."
    exit 1
fi

if [[ ! -e /dev/kvm ]]; then
    echo "ERROR: /dev/kvm not found. KVM is required for x86_64 emulation."
    exit 1
fi

echo "All prerequisites met."
echo ""

# --- Setup (idempotent) ---
echo "=== Setup ==="

# Download system image if needed
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$(dirname "$(dirname "$(command -v sdkmanager)")")}}"
if [[ -d "$SDK_ROOT/$SYSTEM_IMAGE_PATH" ]]; then
    echo "System image already installed."
else
    echo "Downloading system image (android-29 x86_64)..."
    yes | sdkmanager "$SYSTEM_IMAGE" || true
fi

# Create AVD if needed
if avdmanager list avd 2>/dev/null | grep -q "Name: $AVD_NAME"; then
    echo "AVD '$AVD_NAME' already exists."
else
    echo "Creating AVD '$AVD_NAME'..."
    echo "no" | avdmanager create avd \
        --name "$AVD_NAME" \
        --package "$SYSTEM_IMAGE" \
        --device "pixel" \
        --force
fi

# Clone rootAVD if needed
if [[ -d "$ROOTAVD_DIR" ]]; then
    echo "rootAVD already cloned."
else
    echo "Cloning rootAVD..."
    mkdir -p "$(dirname "$ROOTAVD_DIR")"
    git clone "$ROOTAVD_REPO" "$ROOTAVD_DIR"
fi

echo ""

# --- Helper: wait for boot ---
wait_for_boot() {
    local timeout=$1
    local elapsed=0
    echo "Waiting for emulator to boot (timeout: ${timeout}s)..."
    while [[ $elapsed -lt $timeout ]]; do
        if adb shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
            echo "Emulator booted after ${elapsed}s."
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "ERROR: emulator did not boot within ${timeout}s"
    return 1
}

# --- Helper: start emulator ---
start_emulator() {
    local extra_args=("$@")
    emulator -avd "$AVD_NAME" \
        -no-snapshot \
        -no-audio \
        -no-window \
        -gpu swiftshader_indirect \
        "${extra_args[@]}" &
    EMULATOR_PID=$!
    echo "Emulator started (pid $EMULATOR_PID)"

    # Wait for adb to see the device
    adb wait-for-device

    if ! wait_for_boot "$BOOT_TIMEOUT"; then
        echo "ERROR: boot timed out"
        exit 1
    fi
}

# --- Helper: kill emulator ---
kill_emulator() {
    if [[ -n "$EMULATOR_PID" ]] && kill -0 "$EMULATOR_PID" 2>/dev/null; then
        echo "Shutting down emulator..."
        kill "$EMULATOR_PID" 2>/dev/null || true
        wait "$EMULATOR_PID" 2>/dev/null || true
        EMULATOR_PID=""
        sleep 2
    fi
}

# --- Root the AVD with Magisk (if not already rooted) ---
echo "=== Rooting AVD with Magisk ==="

# We need to boot once to check if Magisk is installed, and to let rootAVD patch.
start_emulator

# Check if already rooted
if adb shell su -c "magisk -v" 2>/dev/null | grep -qE "^[0-9]"; then
    echo "AVD is already rooted with Magisk."
    ALREADY_ROOTED=true
else
    ALREADY_ROOTED=false
    echo "Magisk not detected. Patching with rootAVD..."

    # Find the ramdisk to patch
    RAMDISK_PATH="$SDK_ROOT/$SYSTEM_IMAGE_PATH/ramdisk.img"
    if [[ ! -f "$RAMDISK_PATH" ]]; then
        echo "ERROR: ramdisk not found at $RAMDISK_PATH"
        exit 1
    fi

    kill_emulator

    # Run rootAVD — pipe "1" to select Stable Magisk
    echo "Patching ramdisk with rootAVD (selecting Stable Magisk)..."
    (cd "$ROOTAVD_DIR" && echo "1" | bash rootAVD.sh "$RAMDISK_PATH")

    echo "rootAVD patching complete."
    echo ""

    # Boot the rooted emulator
    echo "=== Booting rooted emulator ==="
    start_emulator -wipe-data
fi

# If we were already rooted, emulator is still running from the check above.
# If we just rooted, we booted fresh above.

# Verify Magisk is working
echo "Verifying Magisk..."
MAGISK_VER="$(adb shell su -c "magisk -v" 2>/dev/null || echo "")"
if echo "$MAGISK_VER" | grep -qE "^[0-9]"; then
    echo "Magisk version: $MAGISK_VER"
else
    echo "ERROR: Magisk not working after rooting. su -c 'magisk -v' returned: $MAGISK_VER"
    exit 1
fi

echo ""

# --- Build and install module ---
echo "=== Installing adb_root module ==="

# Build the zip
make zip

# Determine zip filename
ZIP="$(ls -1 adb_root-*.zip | head -1)"
if [[ -z "$ZIP" ]]; then
    echo "ERROR: make zip did not produce a zip file"
    exit 1
fi
echo "Built: $ZIP"

# Push and install
adb push "$ZIP" /sdcard/
echo "Installing module via Magisk..."
INSTALL_OUT="$(adb shell su -c "magisk --install-module /sdcard/$ZIP" 2>&1)"
echo "$INSTALL_OUT"

# Reboot to activate module
echo "Rebooting to activate module..."
adb shell su -c reboot
sleep 5
adb wait-for-device

if ! wait_for_boot "$BOOT_TIMEOUT"; then
    echo "ERROR: emulator did not boot after module install"
    exit 1
fi

# Give service.sh time to run
sleep 10

echo ""

# --- Verification ---
echo "=== Verification ==="
echo ""

# 1. Module directory exists
if adb shell su -c "test -d /data/adb/modules/adb_root && echo yes" 2>/dev/null | grep -q "yes"; then
    pass "module directory exists: /data/adb/modules/adb_root"
else
    fail "module directory not found: /data/adb/modules/adb_root"
fi

# 2. Binary overlay: md5sum of /system/bin/adbd matches module's copy
SYSTEM_MD5="$(adb shell md5sum /system/bin/adbd 2>/dev/null | awk '{print $1}')"
MODULE_MD5="$(adb shell su -c "md5sum /data/adb/modules/adb_root/system/bin/adbd" 2>/dev/null | awk '{print $1}')"
if [[ -n "$SYSTEM_MD5" && "$SYSTEM_MD5" = "$MODULE_MD5" ]]; then
    pass "binary overlay active: /system/bin/adbd matches module copy ($SYSTEM_MD5)"
else
    fail "binary overlay mismatch: system=$SYSTEM_MD5 module=$MODULE_MD5"
fi

# 3. adbd running as root (uid 0)
ADBD_PID="$(adb shell pidof adbd 2>/dev/null | tr -d '[:space:]')"
if [[ -n "$ADBD_PID" ]]; then
    ADBD_UID="$(adb shell su -c "stat -c %u /proc/$ADBD_PID" 2>/dev/null | tr -d '[:space:]')"
    if [[ "$ADBD_UID" = "0" ]]; then
        pass "adbd running as root (pid $ADBD_PID, uid $ADBD_UID)"
    else
        fail "adbd not running as root (pid $ADBD_PID, uid $ADBD_UID)"
    fi
else
    fail "adbd not running (pidof returned empty)"
fi

# 4. SELinux rules loaded
SEPOLICY_OUT="$(adb shell su -c "magiskpolicy --print-rules" 2>/dev/null || echo "")"
if echo "$SEPOLICY_OUT" | grep -q "adbd"; then
    pass "SELinux rules loaded (magiskpolicy contains adbd rules)"
else
    fail "SELinux rules not found for adbd in magiskpolicy output"
fi

# 5. Boot count state file created
STATE_OUT="$(adb shell su -c "cat /data/adb/modules/adb_root/state.sh" 2>/dev/null || echo "")"
if echo "$STATE_OUT" | grep -q "BOOT_COUNT=1"; then
    pass "state.sh exists with BOOT_COUNT=1"
else
    fail "state.sh missing or unexpected content: $STATE_OUT"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
