#!/usr/bin/env bash
# sync-aosp.sh — Initialize and sync the minimal set of AOSP projects
#                needed to build adbd, then trim the tree to save space.
#
# Usage: sync-aosp.sh <AOSP_TAG> <project-list-file>

set -euo pipefail

AOSP_TAG="${1:?Usage: sync-aosp.sh <AOSP_TAG> <project-list-file>}"
PROJECT_LIST="${2:?Usage: sync-aosp.sh <AOSP_TAG> <project-list-file>}"

# ── repo init ──
repo init \
    -u https://android.googlesource.com/platform/manifest \
    -b "${AOSP_TAG}" --depth=1

# ── Read project list (strip comments and blank lines) ──
mapfile -t projects < <(sed 's/#.*//; /^[[:space:]]*$/d' "$PROJECT_LIST")

# ── repo sync ──
repo sync -c --no-tags --no-clone-bundle \
    -j"$(nproc)" --force-sync \
    "${projects[@]}"

# ── Trim clang prebuilts (~5 GB) — adbd only needs clang-r353983c ──
cd prebuilts/clang/host/linux-x86
ls -d clang-* | grep -v 'clang-r353983' | xargs rm -rf
cd /aosp

# ── Remove repo metadata ──
rm -rf .repo

# ── Prune unneeded subdirectories ──
find bionic -xtype l -delete
rm -rf frameworks/native/cmds
rm -rf frameworks/native/services
rm -rf frameworks/native/opengl/tests
rm -rf prebuilts/misc/common/android-support-test
rm -rf system/core/adb/fastdeploy
rm -rf system/core/libnativeloader/test
rm -rf system/core/rootdir
