# Changelog

## v2.0
- Add service.sh to ensure adbd runs as root after boot
- Add system.prop to set service.adb.root=1
- Add Magisk auto-updater support (updateJson)
- Add CI workflows (ShellCheck, build verification, automated releases)
- Add Dependabot for GitHub Actions updates

## v1.0
- Initial release
- Patched adbd binary for aarch64 Android 9/10
- SELinux policy rules for root adbd
