getprop = $(shell grep "^$(1)=" module.prop | head -n1 | cut -d'=' -f2)

MODNAME ?= $(call getprop,id)
MODVER ?= $(call getprop,version)
ZIP = $(MODNAME)-$(MODVER).zip

all: $(ZIP)

zip: $(ZIP)

$(ZIP): clean
	zip -r9 $(ZIP) . -x $(MODNAME)-*.zip LICENSE README.md CHANGELOG.md CLAUDE.md update.json cliff.toml .gitignore .gitattributes Makefile Dockerfile build-adbd.sh /patches* /tests* /hooks/* /.git* /.github* /.claude*

install: $(ZIP)
	adb push $(ZIP) /sdcard/ && \
	echo '/data/adb/magisk/busybox unzip -p "/sdcard/$(ZIP)" META-INF/com/google/android/update-binary | /data/adb/magisk/busybox sh /proc/self/fd/0 x x "/sdcard/$(ZIP)"' | adb shell su -c sh - && \
	adb shell rm -f "/sdcard/$(ZIP)"

clean:
	rm -f *.zip

build-adbd:
	DOCKER_BUILDKIT=1 docker build --target=binary --output=system/bin/ .

test-adbd:
	./tests/test-adbd-binary.sh system/bin/adbd

update:
	curl -fS -o META-INF/com/google/android/update-binary.tmp https://raw.githubusercontent.com/topjohnwu/Magisk/master/scripts/module_installer.sh && \
	mv META-INF/com/google/android/update-binary.tmp META-INF/com/google/android/update-binary

setup:
	ln -sf ../../hooks/pre-commit .git/hooks/pre-commit
	ln -sf ../../hooks/commit-msg .git/hooks/commit-msg

changelog:
	git-cliff --config cliff.toml --output CHANGELOG.md

.PHONY: all zip install clean setup update changelog build-adbd test-adbd
