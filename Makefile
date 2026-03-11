getprop = $(shell cat module.prop | grep "^$(1)=" | head -n1 | cut -d'=' -f2)

MODNAME ?= $(call getprop,id)
MODVER ?= $(call getprop,version)
ZIP = $(MODNAME)-$(MODVER).zip

all: $(ZIP)

zip: $(ZIP)

$(ZIP): clean
	zip -r9 $(ZIP) . -x $(MODNAME)-*.zip LICENSE README.md CHANGELOG.md CLAUDE.md update.json .gitignore .gitattributes Makefile /hooks/* /.git* /.github* /.claude*

install: $(ZIP)
	adb push $(ZIP) /sdcard/ && \
	echo '/data/adb/magisk/busybox unzip -p "/sdcard/$(ZIP)" META-INF/com/google/android/update-binary | /data/adb/magisk/busybox sh /proc/self/fd/0 x x "/sdcard/$(ZIP)"' | adb shell su -c sh - && \
	adb shell rm -f "/sdcard/$(ZIP)"

clean:
	rm -f *.zip

update:
	curl -fS -o META-INF/com/google/android/update-binary.tmp https://raw.githubusercontent.com/topjohnwu/Magisk/master/scripts/module_installer.sh && \
	mv META-INF/com/google/android/update-binary.tmp META-INF/com/google/android/update-binary

setup:
	ln -sf ../../hooks/pre-commit .git/hooks/pre-commit

.PHONY: all zip install clean setup update
