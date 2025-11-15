SHELL := /bin/bash
.ONESHELL:

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
S := $(ROOT)/scripts

.PHONY: help all linux android android-emulator macos ios windows clean test
.DEFAULT_GOAL := help

help:
	@echo "Usage: make <target>";
	@echo "Available targets:";
	@awk -F: '/^[A-Za-z0-9_.-]+:([^=]|$$)/ {print "  " $$1}' $(MAKEFILE_LIST) \
		| sed 's/^\s*$$//' | sort -u

all: linux android

linux:
	$(S)/build_linux.sh
	cd $(ROOT)/icp_autorun && flutter build linux && flutter run -d linux

android:
	$(S)/build_android.sh
	cd $(ROOT)/icp_autorun && flutter build apk

android-emulator:
	$(S)/run_android_emulator.sh

macos:
	$(S)/build_macos.sh
	cd $(ROOT)/icp_autorun && flutter build macos

ios:
	$(S)/build_ios.sh
	cd $(ROOT)/icp_autorun && flutter build ios --no-codesign

windows:
	$(S)/build_windows.sh
	cd $(ROOT)/icp_autorun && flutter build windows

clean:
	rm -rf $(ROOT)/icp_autorun/android/app/src/main/jniLibs/* || true
	rm -f $(ROOT)/icp_autorun/build/linux/x64/*/bundle/lib/libicp_core.* || true

test:
	@set -euo pipefail
	@echo "==> Running Flutter analysis and tests"
	cd $(ROOT)/icp_autorun && flutter analyze && flutter test
	@echo "==> Running Rust linting and tests"
	cargo clippy --benches --tests --all-features
	cargo clippy
	cargo fmt --all
	@if cargo nextest --help >/dev/null 2>&1; then \
	  cargo nextest run ; \
	else \
	  echo "cargo-nextest not found; running cargo test" ; \
	  cargo test ; \
	fi
