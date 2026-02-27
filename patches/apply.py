#!/usr/bin/env python3
"""Apply adbd-root patches to AOSP system/core source tree.

Usage: python3 apply.py /path/to/system/core
"""
import re
import sys
import os


def patch_file(path, description, old, new):
    with open(path) as f:
        text = f.read()
    if old not in text:
        print(f"WARNING: Expected text not found in {path} for: {description}")
        print(f"  Looking for: {old[:80]}...")
        sys.exit(1)
    text = text.replace(old, new, 1)
    with open(path, "w") as f:
        f.write(text)
    print(f"  Patched: {description}")


def patch_file_regex(path, description, pattern, replacement, flags=0):
    with open(path) as f:
        text = f.read()
    new_text, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count == 0:
        print(f"WARNING: Pattern not matched in {path} for: {description}")
        sys.exit(1)
    with open(path, "w") as f:
        f.write(new_text)
    print(f"  Patched: {description}")


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} /path/to/system/core")
        sys.exit(1)

    core = sys.argv[1]
    main_cpp = os.path.join(core, "adb/daemon/main.cpp")
    restart_cpp = os.path.join(core, "adb/daemon/restart_service.cpp")

    print(f"Patching {main_cpp}")

    # 1. should_drop_capabilities_bounding_set() → always return false
    # This function may contain nested braces, so use DOTALL with non-greedy .+?
    patch_file_regex(
        main_cpp,
        "should_drop_capabilities_bounding_set() → return false",
        r"static bool should_drop_capabilities_bounding_set\(\) \{.+?\n\}",
        "static bool should_drop_capabilities_bounding_set() {\n    return false;\n}",
        flags=re.DOTALL,
    )

    # 2. should_drop_privileges() → always return false
    # This function body contains nested braces, so we can't use [^}]+
    patch_file_regex(
        main_cpp,
        "should_drop_privileges() → return false",
        r"static bool should_drop_privileges\(\) \{.+?\n\}",
        "static bool should_drop_privileges() {\n    return false;\n}",
        flags=re.DOTALL,
    )

    # 3. Remove is_device_unlocked() — no longer called after privilege patches
    patch_file_regex(
        main_cpp,
        "remove is_device_unlocked() (now unused)",
        r"static inline bool is_device_unlocked\(\) \{[^}]+\}\n*",
        "",
    )

    # 4. Replace the #if ALLOW_ADBD_NO_AUTH block with unconditional auth_required = false
    patch_file_regex(
        main_cpp,
        "auth_required → unconditionally false",
        r"#if defined\(ALLOW_ADBD_NO_AUTH\).*?#endif",
        "    auth_required = false;",
        flags=re.DOTALL,
    )

    print(f"Patching {restart_cpp}")

    # 5. Remove debuggability check in restart_root_service()
    patch_file(
        restart_cpp,
        "remove debuggability check in restart_root_service()",
        '    if (!__android_log_is_debuggable()) {\n'
        '        WriteFdExactly(fd.get(), "adbd cannot run as root in production builds\\n");\n'
        '        return;\n'
        '    }\n',
        "",
    )

    # ── Static linking patches for adbd binary ──
    android_bp = os.path.join(core, "adb/Android.bp")
    print(f"Patching {android_bp}")

    # 6. Enable static_executable and disable implicit STL shared lib
    patch_file(
        android_bp,
        'adbd: add static_executable: true and stl: "none"',
        '    name: "adbd",',
        '    name: "adbd",\n'
        '    static_executable: true,\n'
        '    stl: "none",',
    )

    # 7. Convert shared_libs to static_libs and add bionic/STL static libs
    patch_file(
        android_bp,
        "adbd: convert shared_libs to static_libs with bionic",
        '    shared_libs: [\n'
        '        "libadbd",\n'
        '        "libadbd_services",\n'
        '        "libbase",\n'
        '        "libcap",\n'
        '        "libcrypto",\n'
        '        "libcutils",\n'
        '        "liblog",\n'
        '        "libminijail",\n'
        '        "libselinux",\n'
        '    ]',
        '    static_libs: [\n'
        '        "libadbd",\n'
        '        "libadbd_services",\n'
        '        "libbase",\n'
        '        "libcap",\n'
        '        "libcrypto",\n'
        '        "libcutils",\n'
        '        "liblog",\n'
        '        "libminijail",\n'
        '        "libselinux",\n'
        '        "libasyncio",\n'
        '        "libcrypto_utils",\n'
        '        "libmdnssd",\n'
        '        "libc++_static",\n'
        '        "libc",\n'
        '        "libm",\n'
        '        "libdl",\n'
        '    ]',
    )

    print("All patches applied successfully")


if __name__ == "__main__":
    main()
