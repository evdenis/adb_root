getprop = $(shell grep "^$(1)=" module.prop | head -n1 | cut -d'=' -f2)

MODNAME ?= $(call getprop,id)
MODVER ?= $(call getprop,version)
ZIP = $(MODNAME)-$(MODVER).zip

ARCHES := arm64 arm x86 x86_64

all: $(ZIP)

zip: $(ZIP)

$(ZIP): clean
	zip -r9 $(ZIP) . -x $(MODNAME)-*.zip LICENSE README.md CHANGELOG.md CLAUDE.md update.json cliff.toml .gitignore .gitattributes .dockerignore Makefile Dockerfile build-adbd.sh /docker* /patches* /tests* /hooks/* /.git* /.github* /.claude* /out*

install: $(ZIP)
	adb push $(ZIP) /sdcard/ && \
	echo '/data/adb/magisk/busybox unzip -p "/sdcard/$(ZIP)" META-INF/com/google/android/update-binary | /data/adb/magisk/busybox sh /proc/self/fd/0 x x "/sdcard/$(ZIP)"' | adb shell su -c sh - && \
	adb shell rm -f "/sdcard/$(ZIP)"

clean:
	rm -f *.zip

build-adbd: $(addprefix build-adbd-,$(ARCHES))

build-adbd-%:
	DOCKER_BUILDKIT=1 docker build --build-arg TARGET_ARCH=$* \
	    --target=binary --output=type=local,dest=out/ .
	cp out/adbd system/bin/adbd.$*
	rm -rf out

test-adbd: $(addprefix test-adbd-,$(ARCHES))

test-adbd-%:
	./tests/test-adbd-binary.sh system/bin/adbd.$* $*

test-emulator:
	./tests/test-emulator.sh

update:
	curl -fS -o META-INF/com/google/android/update-binary.tmp https://raw.githubusercontent.com/topjohnwu/Magisk/master/scripts/module_installer.sh && \
	mv META-INF/com/google/android/update-binary.tmp META-INF/com/google/android/update-binary

setup:
	ln -sf ../../hooks/pre-commit .git/hooks/pre-commit
	ln -sf ../../hooks/commit-msg .git/hooks/commit-msg

changelog:
	git-cliff --config cliff.toml --output CHANGELOG.md

.PHONY: all zip install clean setup update changelog build-adbd test-adbd test-emulator
