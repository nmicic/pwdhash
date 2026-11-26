.DEFAULT_GOAL := cli
CC ?= cc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Wpedantic -fstack-protector-strong

.PHONY: all cli test test-macos test-android-core test-android-device build ios simulator install macos verify-macos macos-appstore open-macos android android-release android-screenshots install-android
all: cli ios macos android
cli: .build/cli/pwdhash
.build/cli/pwdhash: src/cli/pwdhash.c
	mkdir -p .build/cli
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $< -o $@
test:
	sh scripts/test.sh
test-macos:
	sh scripts/test-macos.sh
test-android-core:
	sh scripts/test-android-core.sh
test-android-device:
	sh scripts/test-android-device.sh
build: ios
ios:
	sh scripts/build.sh
simulator:
	SDK=iphonesimulator sh scripts/build.sh
install:
	sh scripts/install.sh
macos:
	sh scripts/build-macos.sh
verify-macos: macos
	sh scripts/verify-macos-release.sh
macos-appstore: macos
	sh scripts/package-macos-appstore.sh
open-macos: macos
	open .build/macos/PwdHash.app
android:
	sh scripts/build-android.sh
android-release:
	sh scripts/build-android-release.sh
android-screenshots:
	sh scripts/capture-android-screenshots.sh
install-android:
	sh scripts/install-android.sh
