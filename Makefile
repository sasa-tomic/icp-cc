SHELL := /bin/bash
.ONESHELL:

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
S := $(ROOT)/scripts

.PHONY: help all linux android android-emulator macos ios windows clean
.DEFAULT_GOAL := help

help:
	@echo "Usage: make <target>";
	@echo "Available targets:";
	@awk -F: '/^[A-Za-z0-9_.-]+:([^=]|$$)/ {print "  " $$1}' $(MAKEFILE_LIST) \
		| sed 's/^\s*$$//' | sort -u

all: linux android

linux:
	$(S)/build_linux.sh
	cd $(ROOT)/icp_identity_manager && flutter build linux && flutter run -d linux

android:
	$(S)/build_android.sh
	cd $(ROOT)/icp_identity_manager && flutter build apk

android-emulator:
	$(S)/run_android_emulator.sh

macos:
	$(S)/build_macos.sh
	cd $(ROOT)/icp_identity_manager && flutter build macos

ios:
	$(S)/build_ios.sh
	cd $(ROOT)/icp_identity_manager && flutter build ios --no-codesign

windows:
	$(S)/build_windows.sh
	cd $(ROOT)/icp_identity_manager && flutter build windows

clean:
	rm -rf $(ROOT)/icp_identity_manager/android/app/src/main/jniLibs/* || true
	rm -f $(ROOT)/icp_identity_manager/build/linux/x64/*/bundle/lib/libicp_core.* || true
