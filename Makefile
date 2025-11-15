SHELL := /bin/bash
.ONESHELL:

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
S := $(ROOT)/scripts

.PHONY: help all linux android android-emulator macos ios windows clean distclean test
.DEFAULT_GOAL := help

help:
	@echo "Usage: make <target>";
	@echo "Available targets:";
	@awk -F: '/^[A-Za-z0-9_.-]+:([^=]|$$)/ {print "  " $$1}' $(MAKEFILE_LIST) \
		| sed 's/^\s*$$//' | sort -u

all: linux android

linux:
	$(S)/build_linux.sh
	cd $(ROOT)/apps/autorun_flutter && flutter build linux && flutter run -d linux

android:
	$(S)/build_android.sh
	cd $(ROOT)/apps/autorun_flutter && flutter build apk

android-emulator:
	$(S)/run_android_emulator.sh

macos:
	$(S)/build_macos.sh
	cd $(ROOT)/apps/autorun_flutter && flutter build macos

ios:
	$(S)/build_ios.sh
	cd $(ROOT)/apps/autorun_flutter && flutter build ios --no-codesign

windows:
	$(S)/build_windows.sh
	cd $(ROOT)/apps/autorun_flutter && flutter build windows

clean:
	rm -rf $(ROOT)/apps/autorun_flutter/android/app/src/main/jniLibs/* || true
	rm -rf $(ROOT)/apps/autorun_flutter/build || true
	rm -f $(ROOT)/apps/autorun_flutter/build/linux/x64/*/bundle/lib/libicp_core.* || true
	rm -rf $(ROOT)/apps/autorun_flutter/linux/flutter/ephemeral || true

distclean: clean
	rm -rf $(ROOT)/target || true
	rm -rf $(ROOT)/apps/autorun_flutter/.dart_tool || true
	rm -rf $(ROOT)/apps/autorun_flutter/.gradle || true

test:
	@set -euo pipefail
	@echo "==> Running Flutter analysis and tests"
	cd $(ROOT)/apps/autorun_flutter && flutter analyze && flutter test
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
