#!/usr/bin/env bash
#
# Binary sanity tests for the adbd binary.
# Usage: ./tests/test-adbd-binary.sh [path/to/adbd]
#

set -euo pipefail

BINARY="${1:-system/bin/adbd}"

if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: binary not found: $BINARY"
    exit 1
fi

PASS=0
FAIL=0

pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

FILE_OUT="$(file "$BINARY")"

# 1. ELF format + aarch64
if echo "$FILE_OUT" | grep -q "ELF 64-bit LSB executable, ARM aarch64"; then
    pass "ELF 64-bit aarch64 executable"
else
    fail "ELF 64-bit aarch64 executable — got: $FILE_OUT"
fi

# 2. Statically linked
if echo "$FILE_OUT" | grep -q "statically linked"; then
    pass "statically linked"
else
    fail "statically linked — got: $FILE_OUT"
fi

# 3. Stripped
if echo "$FILE_OUT" | grep -q "stripped" && ! echo "$FILE_OUT" | grep -q "not stripped"; then
    pass "stripped"
else
    fail "stripped — got: $FILE_OUT"
fi

# 4. Android target
if echo "$FILE_OUT" | grep -q "for Android"; then
    pass "built for Android"
else
    fail "built for Android — got: $FILE_OUT"
fi

# 5. No dynamic section (no NEEDED libs)
READELF_D="$(readelf -d "$BINARY" 2>&1 || true)"
if echo "$READELF_D" | grep -qi "no dynamic section\|there is no dynamic section"; then
    pass "no dynamic section"
else
    fail "no dynamic section — got: $READELF_D"
fi

# 6. ELF type is EXEC (not DYN/shared)
READELF_H="$(readelf -h "$BINARY")"
if echo "$READELF_H" | grep -q "Type:.*EXEC"; then
    pass "ELF type is EXEC"
else
    fail "ELF type is EXEC — got: $(echo "$READELF_H" | grep 'Type:')"
fi

# 7. Machine is AArch64
if echo "$READELF_H" | grep -q "Machine:.*AArch64"; then
    pass "machine is AArch64"
else
    fail "machine is AArch64 — got: $(echo "$READELF_H" | grep 'Machine:')"
fi

# 8. Reasonable file size (500KB–10MB)
SIZE="$(stat --format='%s' "$BINARY" 2>/dev/null || stat -f '%z' "$BINARY")"
MIN=$((500 * 1024))
MAX=$((10 * 1024 * 1024))
if [[ "$SIZE" -ge "$MIN" && "$SIZE" -le "$MAX" ]]; then
    pass "file size is reasonable ($(( SIZE / 1024 ))KB)"
else
    fail "file size out of range: $SIZE bytes (expected ${MIN}–${MAX})"
fi

# 9. Contains adbd strings
if strings "$BINARY" | grep -c "adbd" > /dev/null; then
    pass "contains 'adbd' string"
else
    fail "binary does not contain 'adbd' string"
fi

# Wrap QEMU commands in a PID namespace so 32-bit bionic gets a low PID.
# 32-bit Android's pthread_mutex_t stores the owner PID in 16 bits and
# aborts if PID > 65535.  A new PID namespace starts numbering from 1.
# adbd is a daemon — it may not exit on its own, so we bound each attempt
# with a timeout.  2s is plenty for the binary to reach socketpair/crash;
# keeping it short also avoids capturing huge strace output (~100K lines/s).
QEMU_TIMEOUT=2
run_qemu() {
    # Prefer privileged PID namespace: avoids user-namespace setgroups
    # restrictions that crash x86 adbd before it reaches socketpair.
    # sudo -n fails immediately if a password is required (no hanging).
    if sudo -n true 2>/dev/null; then
        sudo unshare --pid --fork --mount-proc \
            timeout -k 3 "$QEMU_TIMEOUT" "$@"
        return
    fi
    # No namespace (may fail for 32-bit on high-PID hosts)
    timeout -k 3 "$QEMU_TIMEOUT" "$@"
}


# 10–12. QEMU smoke tests
if command -v qemu-aarch64-static >/dev/null 2>&1; then
    QEMU="qemu-aarch64-static"

    # 10. --version prints ADB version string with a version number
    QEMU_VER="$(ulimit -c 0; run_qemu "$QEMU" "$BINARY" --version 2>&1 || true)"
    if echo "$QEMU_VER" | grep -qE "Android Debug Bridge.*version [0-9]+\.[0-9]+\.[0-9]+"; then
        pass "QEMU --version: $QEMU_VER"
    else
        fail "QEMU --version — output: $QEMU_VER"
    fi

    # 11–12. Strace shows daemon reaches socket creation and Android logging.
    # Write to a temp file: adbd running as root produces massive strace
    # output (~100K lines/s) that can overwhelm a shell variable.
    STRACE_LOG="$(mktemp)"
    trap 'rm -f "$STRACE_LOG"' EXIT
    ulimit -c 0
    run_qemu "$QEMU" -strace "$BINARY" >"$STRACE_LOG" 2>&1 || true

    if grep -qi "socketpair" "$STRACE_LOG"; then
        pass "QEMU strace shows socketpair (daemon init reached)"
    else
        fail "QEMU strace missing socketpair — output: $(tail -5 "$STRACE_LOG")"
    fi

    if grep -q "/dev/socket/logdw" "$STRACE_LOG"; then
        pass "QEMU strace shows /dev/socket/logdw access (Android logging)"
    else
        fail "QEMU strace missing /dev/socket/logdw — output: $(tail -5 "$STRACE_LOG")"
    fi
else
    echo "SKIP: QEMU smoke tests (qemu-aarch64-static not installed)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
