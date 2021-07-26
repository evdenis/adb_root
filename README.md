# ADB Root

Android 9/10 only. Will not work on Android 11.

You don't need this module if you don't know what is "adb root". It's not an
ordinary root (su), it's the adbd daemon running on your phone with root rights.
adb root allows you to "adb push/pull" to system directories and run such commands
as "adb remount" or "adb disable-verify".

This is a highly insecure magisk module.
Don't forget to disable it once you've done all the things you need.
Don't use it constantly.

This module allows you to run adb daemon from root user. It provides own adbd binary.
The binary obtained from AOSP sources with the following patch that disables props
checks and usb auth. The binary is required because "adb root" can be disabled
in compile time by some vendors. Aarch64 only.

<details>

<summary>Patch:</summary>

```diff
diff --git a/adb/daemon/main.cpp b/adb/daemon/main.cpp
index d064d0d..a520bfd 100644
--- a/adb/daemon/main.cpp
+++ b/adb/daemon/main.cpp
@@ -51,48 +51,11 @@
 static const char* root_seclabel = nullptr;
 
 static bool should_drop_capabilities_bounding_set() {
-#if defined(ALLOW_ADBD_ROOT)
-    if (__android_log_is_debuggable()) {
-        return false;
-    }
-#endif
-    return true;
+    return false;
 }
 
 static bool should_drop_privileges() {
-#if defined(ALLOW_ADBD_ROOT)
-    // The properties that affect `adb root` and `adb unroot` are ro.secure and
-    // ro.debuggable. In this context the names don't make the expected behavior
-    // particularly obvious.
-    //
-    // ro.debuggable:
-    //   Allowed to become root, but not necessarily the default. Set to 1 on
-    //   eng and userdebug builds.
-    //
-    // ro.secure:
-    //   Drop privileges by default. Set to 1 on userdebug and user builds.
-    bool ro_secure = android::base::GetBoolProperty("ro.secure", true);
-    bool ro_debuggable = __android_log_is_debuggable();
-
-    // Drop privileges if ro.secure is set...
-    bool drop = ro_secure;
-
-    // ... except "adb root" lets you keep privileges in a debuggable build.
-    std::string prop = android::base::GetProperty("service.adb.root", "");
-    bool adb_root = (prop == "1");
-    bool adb_unroot = (prop == "0");
-    if (ro_debuggable && adb_root) {
-        drop = false;
-    }
-    // ... and "adb unroot" lets you explicitly drop privileges.
-    if (adb_unroot) {
-        drop = true;
-    }
-
-    return drop;
-#else
-    return true; // "adb root" not allowed, always drop privileges.
-#endif // ALLOW_ADBD_ROOT
+    return false;
 }
 
 static void drop_privileges(int server_port) {
@@ -183,9 +146,7 @@ int adbd_main(int server_port) {
     // descriptor will always be open.
     adbd_cloexec_auth_socket();
 
-    if (ALLOW_ADBD_NO_AUTH && !android::base::GetBoolProperty("ro.adb.secure", false)) {
-        auth_required = false;
-    }
+    auth_required = false;
 
     adbd_auth_init();
 
diff --git a/adb/services.cpp b/adb/services.cpp
index 8518f2e..24f9def 100644
--- a/adb/services.cpp
+++ b/adb/services.cpp
@@ -78,12 +78,6 @@ void restart_root_service(int fd, void *cookie) {
         WriteFdExactly(fd, "adbd is already running as root\n");
         adb_close(fd);
     } else {
-        if (!__android_log_is_debuggable()) {
-            WriteFdExactly(fd, "adbd cannot run as root in production builds\n");
-            adb_close(fd);
-            return;
-        }
-
         android::base::SetProperty("service.adb.root", "1");
         WriteFdExactly(fd, "restarting adbd as root\n");
         adb_close(fd);
```

</details>

## How to install:

Stable release:
1. Dowload latest adb_root.zip from releases page
   https://github.com/evdenis/adb_root/releases
2. MagiskManager -> Modules + Downloads/adb_root.zip -> Reboot

Master branch:
1. git clone https://github.com/evdenis/adb_root
2. cd adb_root
3. make install

## Support

- [Telegram](https://t.me/joinchat/GsJfBBaxozXvVkSJhm0IOQ)
- [XDA Thread](https://forum.xda-developers.com/apps/magisk/module-debugging-modules-adb-root-t4050041)
