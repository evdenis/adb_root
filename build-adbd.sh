#!/bin/bash
# build-adbd.sh — Build adbd using the AOSP Soong build system
#
# This script is invoked inside the Docker build container after
# repo sync and patch application.
#
# It uses the official AOSP build system (Soong) to compile adbd,
# which correctly resolves all dependencies and uses the exact
# same toolchain as upstream AOSP.

set -eo pipefail

cd /aosp

# Allow partial tree — skip modules whose deps are in un-synced repos
export ALLOW_MISSING_DEPENDENCIES=true

# Disable the APEX libraries check. In a partial tree build, bionic libs
# (libc, libdl, libm) end up in the system image instead of APEX containers.
# This is fine — we only care about the adbd binary, not system image layout.
export DISABLE_APEX_LIBS_ABSENCE_CHECK=true

# Create stub VNDK directories to satisfy the build system's version check.
# The aosp_arm64 product config requires VNDK snapshots that we haven't synced.
for v in 27 28 29; do
    mkdir -p "prebuilts/vndk/v${v}/arm64"
    echo 'cc_prebuilt_library_shared { name: "vndk_v'${v}'_stub", enabled: false }' \
        > "prebuilts/vndk/v${v}/arm64/Android.bp"
done

# Create stub for platform_tools_version genrule.
# This genrule is defined in the 'development' repo which we haven't synced.
# It just generates a header with the version string macro.
mkdir -p build/make/platform_tools_version
cat > build/make/platform_tools_version/Android.bp <<'BPEOF'
genrule {
    name: "platform_tools_version",
    cmd: "echo '#define PLATFORM_TOOLS_VERSION \"29.0.6\"' > $(out)",
    out: ["platform_tools_version.h"],
}
BPEOF

# Replace the versioner tool with a simple script that copies bionic headers
# to the NDK sysroot without clang-based validation. The real versioner needs
# clang builtin headers (stdbool.h) which aren't bundled in prebuilts/clang-tools.
# Since we only need adbd (not a real NDK), skipping validation is fine.
mv prebuilts/clang-tools/linux-x86/bin/versioner \
   prebuilts/clang-tools/linux-x86/bin/versioner.real
cat > prebuilts/clang-tools/linux-x86/bin/versioner <<'VEOF'
#!/bin/bash
# Stub versioner: copies headers to output dir without clang validation
OUT=""
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) OUT="$2"; shift 2 ;;
        -*) shift ;;
        *)  ARGS+=("$1"); shift ;;
    esac
done
if [ -n "$OUT" ] && [ ${#ARGS[@]} -gt 0 ]; then
    mkdir -p "$OUT"
    cp -r "${ARGS[0]}"/* "$OUT"/
fi
VEOF
chmod +x prebuilts/clang-tools/linux-x86/bin/versioner

# ── Stub modules for un-synced repos ──
# These satisfy Soong's module resolution for deps we don't need in adbd.

# libfec_rs — Rust FEC library (not synced)
mkdir -p stubs/libfec_rs
echo "void __libfec_rs_stub(void) {}" > stubs/libfec_rs/stub.c
cat > stubs/libfec_rs/Android.bp <<'BPEOF'
cc_library {
    name: "libfec_rs",
    srcs: ["stub.c"],
    vendor_available: true,
    host_supported: true,
    recovery_available: true,
}
BPEOF

# libgsi + libgsi_headers — from system/gsid (not synced)
mkdir -p system/gsid/include/libgsi
cat > system/gsid/include/libgsi/libgsi.h <<'HEOF'
#pragma once
#include <string>
namespace android {
namespace gsi {
static constexpr char kGsiBootedIndicatorFile[] = "/metadata/gsi/dsu/booted";
static constexpr char kGsiLpNamesFile[] = "/metadata/gsi/dsu/lp_names";
static constexpr char kDsuActiveFile[] = "/metadata/gsi/dsu/active";
static inline bool IsGsiRunning() { return false; }
static inline bool IsGsiInstalled() { return false; }
static inline std::string GetDsuSlot() { return ""; }
}  // namespace gsi
}  // namespace android
HEOF
echo "void __libgsi_stub(void) {}" > system/gsid/stub.c
cat > system/gsid/Android.bp <<'BPEOF'
cc_library {
    name: "libgsi",
    srcs: ["stub.c"],
    export_include_dirs: ["include"],
    recovery_available: true,
    vendor_available: true,
    host_supported: true,
}
cc_library_headers {
    name: "libgsi_headers",
    export_include_dirs: ["include"],
    host_supported: true,
    recovery_available: true,
    vendor_available: true,
}
BPEOF

# system/vold — header stubs for libfs_mgr include_dirs
mkdir -p system/vold
cat > system/vold/KeyBuffer.h <<'HEOF'
#pragma once
#include <string>
namespace android {
namespace vold {
using KeyBuffer = std::string;
}  // namespace vold
}  // namespace android
HEOF
touch system/vold/Android.bp

# ── Eliminate libfs_mgr dependency chain from adbd ──
# adbd only uses libfs_mgr for set_verity and remount services, which are
# not needed for our root adbd. Removing them avoids pulling in libfec/libfec_rs/
# system/vold which require many un-synced repos.

# Stub out set_verity_enable_state_service (dm-verity management)
cat > system/core/adb/daemon/set_verity_enable_state_service.cpp <<'SVEOF'
#include "adb_unique_fd.h"
void set_verity_enabled_state_service(unique_fd, bool) {}
SVEOF

# Stub out remount_service (overlayfs remount, depends on libfs_mgr)
cat > system/core/adb/daemon/remount_service.cpp <<'RSEOF'
#include "adb_unique_fd.h"
#include <string>
void remount_service(unique_fd, const std::string&) {}
bool make_block_device_writable(const std::string&) { return false; }
RSEOF

# Stub out UsbNoPermissionsLongHelpText (client-only function referenced by
# transport.cpp; unresolved in static builds since the client code isn't linked)
cat > system/core/adb/client/usb_no_permissions_stub.cpp <<'UPEOF'
#include <string>
std::string UsbNoPermissionsLongHelpText() { return ""; }
UPEOF
sed -i '/daemon\/main.cpp/a\        "client/usb_no_permissions_stub.cpp",' \
    system/core/adb/Android.bp

# Remove the now-unused library deps from the build graph
sed -i '/"libfs_mgr"/d' system/core/adb/Android.bp
sed -i '/"libfec"/d' system/core/adb/Android.bp
sed -i '/"libfs_mgr"/d' bootable/recovery/bootloader_message/Android.bp

# Disable artifact path enforcement in main.mk. The aosp_arm64 product
# triggers a check that system/bin/remount conflicts with mainline_system
# paths. We only care about building adbd, not producing a valid system image.
# The check uses $(PRODUCT_ENFORCE_ARTIFACT_PATH_REQUIREMENTS) — renaming it
# to a variable that's never set effectively disables enforcement.
sed -i 's/PRODUCT_ENFORCE_ARTIFACT_PATH_REQUIREMENTS/__DISABLED__/g' \
    build/make/core/main.mk

# Source the build environment
# Note: AOSP build scripts use unguarded variables, so -u is not used.
# shellcheck disable=SC1091
source build/envsetup.sh

# Select generic arm64 eng build (eng enables ALLOW_ADBD_ROOT)
lunch aosp_arm64-eng

# Build adbd and its dependencies.
# Use -k to keep going past failures in unrelated modules.
make adbd -j"$(nproc)" -k || true

# The 'make adbd' target builds both core and recovery variants.
# The recovery variant may fail due to un-synced libfs_mgr deps.
# If the install path is missing, copy the core variant directly.
ADBD_INSTALL=out/target/product/generic_arm64/system/bin/adbd
ADBD_SOONG=out/soong/.intermediates/system/core/adb/adbd/android_arm64_armv8-a_core/unstripped/adbd

if [ ! -f "$ADBD_INSTALL" ] && [ -f "$ADBD_SOONG" ]; then
    echo "=== Recovery variant blocked install; copying core variant ==="
    mkdir -p out/target/product/generic_arm64/system/bin
    cp "$ADBD_SOONG" "$ADBD_INSTALL"
    prebuilts/clang/host/linux-x86/clang-r353983c/bin/llvm-strip "$ADBD_INSTALL" || true
fi

if [ ! -f "$ADBD_INSTALL" ]; then
    echo "ERROR: adbd binary was not produced"
    find out/ -name "adbd" -type f 2>/dev/null | head -10
    exit 1
fi

# Ensure the binary is fully stripped (Soong's strip may leave .symtab intact
# for static binaries; llvm-strip removes it)
prebuilts/clang/host/linux-x86/clang-r353983c/bin/llvm-strip "$ADBD_INSTALL" || true

echo "=== Build complete ==="
ls -la "$ADBD_INSTALL"
file "$ADBD_INSTALL"
