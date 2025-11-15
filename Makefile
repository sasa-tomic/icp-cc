SHELL := /bin/bash
.ONESHELL:

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
S := $(ROOT)/scripts

.PHONY: help all linux android android-emulator macos ios windows clean distclean test appwrite-setup appwrite-deploy appwrite-api-server appwrite-api-server-dev appwrite-api-server-prod
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
	@set -eEu
	@echo "==> Running Flutter analysis..."
	@cd $(ROOT)/apps/autorun_flutter && flutter analyze
	@echo "==> Running Flutter tests..."
	@cd $(ROOT)/apps/autorun_flutter && flutter test --machine
	@echo "==> Running Rust linting and tests"
	@cargo clippy --benches --tests --all-features --quiet
	@cargo clippy --quiet
	@cargo fmt --all --quiet
	@cargo nextest run
	@echo "✅ All tests passed!"

# Appwrite deployment targets
appwrite-setup:
	@echo "==> Setting up Appwrite CLI tools"
	@npm install -g appwrite-cli || echo "Appwrite CLI already installed or install failed - please install manually"
	@echo "==> Building Rust deployment tool"
	cd $(ROOT)/appwrite-cli && cargo build --release

appwrite-deploy:
	@echo "==> Deploying ICP Script Marketplace to Appwrite (using unified Rust CLI)"
	cd $(ROOT)/appwrite-cli && ./target/release/appwrite-cli deploy

appwrite-deploy-dry-run:
	@echo "==> Dry run: showing what would be deployed to Appwrite (using unified Rust CLI)"
	cd $(ROOT)/appwrite-cli && ./target/release/appwrite-cli deploy --dry-run

appwrite-deploy-verbose:
	@echo "==> Deploying ICP Script Marketplace to Appwrite (verbose mode, using unified Rust CLI)"
	cd $(ROOT)/appwrite-cli && ./target/release/appwrite-cli deploy --verbose

appwrite-test:
	@echo "==> Testing Appwrite deployment configuration (using unified Rust CLI)"
	cd $(ROOT)/appwrite-cli && ./target/release/appwrite-cli test

appwrite-api-server:
	@echo "==> Starting Appwrite API server (production mode)"
	@cd $(ROOT)/appwrite-api-server && (npm list --production >/dev/null 2>&1 || npm install) && npm start

appwrite-api-server-dev:
	@echo "==> Starting Appwrite API server (development mode)"
	@cd $(ROOT)/appwrite-api-server && (npm list >/dev/null 2>&1 || npm install) && npm run dev

appwrite-api-server-test:
	@echo "==> Testing Appwrite API server"
	@cd $(ROOT)/appwrite-api-server && (npm list >/dev/null 2>&1 || npm install) && npm test
