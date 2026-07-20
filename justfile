# Justfile for ICP-CC project
# Modern replacement for Makefile with better features and cross-platform support
#
# Install Just: https://just.systems/
# Usage: just [target] [args...]

# =============================================================================
# Global Settings
# =============================================================================

set shell := ["bash", "-euo", "pipefail", "-c"]

root := `pwd`
scripts_dir := root + "/scripts"
logs_dir := root + "/logs"
flutter_dir := root + "/apps/autorun_flutter"
api_dir := root + "/backend"

# The Flutter app's on-disk state directory. Follows the same resolution the
# Dart `path_provider` package uses on Linux (`XDG_DATA_HOME` if set, else
# `$HOME/.cache/data`), so wiping works regardless of the box's layout —
# dev (HOME-based), CI containers, or wrappers (e.g. omnigent sets
# XDG_DATA_HOME). Hard-coding only `$HOME/.cache/data/...` leaves state behind
# on layouts that override XDG_DATA_HOME, which contaminates subsequent suite
# runs with stale `scripts.json` / `bookmarks.json`.
state_dir := (if env_var_or_default('XDG_DATA_HOME', '') == '' { env_var('HOME') + '/.cache/data' } else { env_var('XDG_DATA_HOME') }) + '/com.example.icp_autorun'

# API server runtime state
tmp_dir := root + "/.just-tmp"
api_port_file := tmp_dir + "/icp-api.port"
api_pid_file := tmp_dir + "/icp-api.pid"

# Docker compose files - completely separated environments
compose_prod := "docker compose -f docker-compose.prod.yml"
compose_dev := "docker compose -f docker-compose.dev.yml"

# =============================================================================
# Default Target
# =============================================================================

# Show help
default:
    @{{scripts_dir}}/dynamic-just-help.sh

# =============================================================================
# Build Commands
# =============================================================================

# Build all platforms
all: linux android

# Build for Linux
linux:
    @echo "==> Building Linux target..."
    {{scripts_dir}}/build_linux.sh
    cd {{flutter_dir}} && flutter build linux
    @if [ -n "${DISPLAY:-}" ]; then \
        echo "==> DISPLAY is set, running the built app..."; \
        {{flutter_dir}}/build/linux/x64/release/bundle/icp_autorun; \
    else \
        echo "==> DISPLAY not set, skipping app execution"; \
    fi

# Build for Android
android:
    @echo "==> Building Android target..."
    {{scripts_dir}}/build_android.sh
    cd {{flutter_dir}} && flutter build apk
    @if [ -d ~/sync/sasa-privatno/icp-autorun/ ]; then \
        cp -v {{flutter_dir}}/build/app/outputs/flutter-apk/app-release.apk ~/sync/sasa-privatno/icp-autorun/; \
    fi

# Build for macOS
macos:
    @echo "==> Building macOS target..."
    {{scripts_dir}}/build_macos.sh
    cd {{flutter_dir}} && flutter build macos

# Build for iOS (without code signing)
ios:
    @echo "==> Building iOS target..."
    {{scripts_dir}}/build_ios.sh
    cd {{flutter_dir}} && flutter build ios --no-codesign

# Build for Windows
windows:
    @echo "==> Building Windows target..."
    {{scripts_dir}}/build_windows.sh
    cd {{flutter_dir}} && flutter build windows

# =============================================================================
# Testing
# =============================================================================

# Run all tests (Rust + Flutter)
test:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Running tests (output saved to logs/test-output.log)"
    mkdir -p "{{logs_dir}}"
    mkdir -p "{{root}}/.tmp"
    tmp_dir=$(mktemp -d "{{root}}/.tmp/just-test-XXXXXX")
    cleanup() {
        [ "$1" -ne 0 ] && echo "==> Preserving temp dir for debugging: $tmp_dir" >&2 || rm -rf "$tmp_dir"
    }
    trap 'cleanup "$?"' EXIT
    export TMPDIR="$tmp_dir" TEMP="$tmp_dir" TMP="$tmp_dir" XDG_RUNTIME_DIR="$tmp_dir"
    echo "Using temp dir: $tmp_dir"
    just rust-tests
    just flutter-tests
    echo "✅ All tests passed! Full output saved to logs/test-output.log"

# Run Rust tests and linting
rust-tests:
    @echo "==> Rust linting and tests..."
    @cargo clippy --benches --tests --all-features --quiet 2>&1 | tee {{logs_dir}}/test-output.log
    @if grep -qE "(error|warning)" {{logs_dir}}/test-output.log; then echo "❌ Rust clippy found issues!"; exit 1; fi
    @echo "✅ No clippy issues found"
    @cargo fmt --all --quiet 2>&1 | tee -a {{logs_dir}}/test-output.log
    @if grep -qE "(error|warning)" {{logs_dir}}/test-output.log; then echo "❌ Rust formatting issues found!"; exit 1; fi
    @echo "✅ No formatting issues found"
    @cargo nextest run 2>&1 | tee -a {{logs_dir}}/test-output.log
    @if grep -qE "\\bFAILED\\b|\\berror\\b:\\s" {{logs_dir}}/test-output.log; then echo "❌ Rust tests failed!"; exit 1; fi
    @echo "✅ All Rust tests passed"

# Run Flutter tests
flutter-tests:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Running Flutter tests with API server..."
    api_started=0
    cleanup() {
        if [ "$api_started" -eq 1 ]; then
            just api-dev-down
        fi
    }
    trap cleanup EXIT
    echo "==> Building native library for Flutter tests..."
    just linux
    just api-dev-up
    api_started=1
    # Source API environment variables
    if [ -f "{{tmp_dir}}/api-env.sh" ]; then
        source "{{tmp_dir}}/api-env.sh"
        echo "==> Using MARKETPLACE_API_PORT=$MARKETPLACE_API_PORT"
    fi
    # Fresh per-invocation log (NOT append) — avoids stale ❌ false-positives
    # from previous runs accumulating in an append-only log. Same pattern the
    # ux_probe suite uses (see PASS1_LOG / PASS2_LOG). When invoked via the
    # `test` umbrella, rust output has already streamed to stdout; this file is
    # the Flutter-only authoritative archive.
    : > {{logs_dir}}/test-output.log
    echo "==> Running Flutter analysis..."
    cd {{flutter_dir}} && flutter analyze 2>&1 | grep -v "✅ " | tee -a {{logs_dir}}/test-output.log || true
    if grep -qE "error •" {{logs_dir}}/test-output.log; then echo "❌ Flutter analysis found errors!"; exit 1; fi
    echo "✅ No Flutter analysis errors"
    echo "==> Running Flutter tests..."
    # Decide pass/fail by `flutter test`'s OWN exit code (PIPESTATUS[0] = the
    # flutter process, before grep/tee) — NOT by grepping the log. The grep
    # below is a secondary belt-and-braces check on the now-fresh log only.
    set +e
    cd {{flutter_dir}} && flutter test --reporter=github --concurrency=$(nproc) --timeout=360s 2>&1 | grep -v "✅ " | tee -a {{logs_dir}}/test-output.log
    flutter_exit=${PIPESTATUS[0]}
    set -e
    if [ "$flutter_exit" -ne 0 ]; then echo "❌ Flutter tests failed (exit $flutter_exit)!"; exit 1; fi
    if grep -qiE "❌ " {{logs_dir}}/test-output.log; then echo "❌ Flutter tests reported failure markers!"; exit 1; fi
    echo "✅ All Flutter tests passed"

# =============================================================================
# Feature-Specific Testing (for rapid iteration)
# =============================================================================

# Test marketplace features (browse, upload, download)
test-feature name:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{logs_dir}}"
    
    feature_dir="{{flutter_dir}}/test/features/{{name}}"
    
    # Check if feature test directory exists
    if [ ! -d "$feature_dir" ]; then
        # Fall back to pattern matching in existing test files
        echo "==> No feature tests in test/features/{{name}}, searching existing tests..."
        cd {{flutter_dir}} && flutter test --name="{{name}}" --timeout=120s 2>&1 | tee {{logs_dir}}/test-output.log
        exit 0
    fi
    
    echo "==> Testing feature: {{name}}"
    
    # Ensure API server is running for integration tests
    api_started=0
    cleanup() {
        if [ "$api_started" -eq 1 ]; then
            just api-dev-down
        fi
    }
    trap cleanup EXIT
    
    # Check if we need the API server (look for integration tests)
    if ls "$feature_dir"/*_test.dart 2>/dev/null | xargs grep -l "MarketplaceOpenApiService\|api.*test" 2>/dev/null; then
        echo "==> Starting API server for integration tests..."
        just api-dev-up
        api_started=1
        if [ -f "{{tmp_dir}}/api-env.sh" ]; then
            source "{{tmp_dir}}/api-env.sh"
        fi
    fi
    
    # Run the feature tests
    cd {{flutter_dir}} && flutter test "$feature_dir" --timeout=180s 2>&1 | tee {{logs_dir}}/test-output.log

    # Detect Flutter's real failure markers: the live counter goes negative on
    # failure (e.g. "00:01 +5 -1:") or the summary reads "Some tests failed.".
    # Do NOT match "error:" — benign debugPrint output in negative-path widget
    # tests trips a loose substring match (false failure).
    if grep -qE "Some tests failed|: \+[0-9]+ -[1-9]" {{logs_dir}}/test-output.log; then
        echo "❌ Feature tests failed!"
        exit 1
    fi
    echo "✅ Feature tests passed: {{name}}"

# Quick test without API server (unit tests only)
test-unit:
    @echo "==> Running unit tests only (no API server)..."
    cd {{flutter_dir}} && flutter test test/utils test/models --timeout=60s

# Test marketplace specifically
test-marketplace:
    @just test-feature marketplace

# Test scripts/execution specifically
test-scripts:
    @just test-feature scripts

# Test profile/account specifically
test-profile:
    @just test-feature profile

# Watch mode for rapid development
test-watch name="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{name}}" ]; then
        cd {{flutter_dir}} && flutter test test/features/{{name}} --watch
    else
        cd {{flutter_dir}} && flutter test --watch
    fi

# =============================================================================
# R-3 WU-1 — QuickJS-on-Web browser verification (headless Chromium)
# =============================================================================
#
# The QuickJS engine (lib/rust/web/quickjs_engine.dart) is browser-only
# (dart:js_interop can't run in the VM — see plan §2.3). This target is the
# headless-Chrome test path: it builds the probe entrypoint
# (tool/web_probe_main.dart), serves build/web, loads it in headless Chromium
# via Playwright, and asserts eval + memory-limit + interrupt-handler all work
# through the Dart interop layer. Reused by every R-3a parity WU.
#
# Requires: a Playwright Chromium browser (auto-installed by
# `npx playwright install chromium`, or present in ~/.cache/ms-playwright/).
verify-quickjs-web:
    #!/usr/bin/env bash
    set -euo pipefail
    probe_dir="{{root}}/scripts/quickjs_web_probe"
    echo "==> Installing Playwright harness deps (idempotent)..."
    cd "$probe_dir" && npm install --no-audit --no-fund --omit=dev >/dev/null 2>&1
    if ! node -e "require('playwright')" 2>/dev/null; then
        echo "==> Playwright Chromium not found in cache; installing browser..."
        npx playwright install chromium
    fi
    echo "==> Building probe web app (flutter build web --target=tool/web_probe_main.dart)..."
    cd {{flutter_dir}} && flutter build web --target=tool/web_probe_main.dart
    echo "==> Running headless-Chromium verification (foreground, timeout-bounded)..."
    timeout 120 node "$probe_dir/verify.js"

# R-3 WU-2/WU-3 — QuickJS-on-Web PARITY verification (golden vectors).
#
# Builds the parity-suite probe entrypoint
# (tool/web_probe_parity_main.dart), serves build/web, loads it in headless
# Chromium via Playwright, and asserts the WebQuickJsEngine produces the SAME
# envelopes as the native engine for the full jsExec + jsApp golden-vector
# catalogue (the parity bar — plan §3 WU-2/WU-3). Reuses the same
# quickjs_web_probe harness deps as verify-quickjs-web.
verify-quickjs-web-parity:
    #!/usr/bin/env bash
    set -euo pipefail
    probe_dir="{{root}}/scripts/quickjs_web_probe"
    echo "==> Installing Playwright harness deps (idempotent)..."
    cd "$probe_dir" && npm install --no-audit --no-fund --omit=dev >/dev/null 2>&1
    if ! node -e "require('playwright')" 2>/dev/null; then
        echo "==> Playwright Chromium not found in cache; installing browser..."
        npx playwright install chromium
    fi
    echo "==> Building parity probe web app (flutter build web --target=tool/web_probe_parity_main.dart)..."
    cd {{flutter_dir}} && flutter build web --target=tool/web_probe_parity_main.dart
    echo "==> Running headless-Chromium parity verification (foreground, timeout-bounded)..."
    timeout 180 node "$probe_dir/verify_parity.js"

# R-3 WU-4 — QuickJS-on-Web PRODUCTION-PATH verification.
#
# Builds the production-path probe (tool/web_probe_app_main.dart), which runs the
# shipped 01_hello_world.js through the REAL stack (probeQuickJsReadiness ->
# RustScriptBridge -> ScriptAppRuntime) and asserts init/view/update work on
# Web. This is the WU-4 bar: "a real script actually runs in the built web app".
verify-quickjs-web-app:
    #!/usr/bin/env bash
    set -euo pipefail
    probe_dir="{{root}}/scripts/quickjs_web_probe"
    echo "==> Installing Playwright harness deps (idempotent)..."
    cd "$probe_dir" && npm install --no-audit --no-fund --omit=dev >/dev/null 2>&1
    if ! node -e "require('playwright')" 2>/dev/null; then
        echo "==> Playwright Chromium not found in cache; installing browser..."
        npx playwright install chromium
    fi
    echo "==> Building production-path probe web app (flutter build web --target=tool/web_probe_app_main.dart)..."
    cd {{flutter_dir}} && flutter build web --target=tool/web_probe_app_main.dart
    echo "==> Running headless-Chromium production-path verification (foreground, timeout-bounded)..."
    timeout 180 node "$probe_dir/verify_app.js"

# =============================================================================
# R-3b WU-0 — agent-js IC-agent browser PoC (headless Chromium, REAL IC query)
# =============================================================================
#
# Proves the browser→backend-proxy→IC-boundary-node path end-to-end with ONE
# real anonymous canister query (ICP ledger `symbol` → "ICP"). Starts the
# backend (for the /api/v1/ic CORS byte-relay proxy, WU-1), builds the
# Flutter-free probe entrypoint (tool/web_probe_agent_main.dart) pointed at the
# proxy, serves build/web, loads it in headless Chromium, and asserts the
# agent-js round-trip succeeded. The agent routes through the proxy because
# ic0.app sends no CORS headers for /api/v2/* (plan §7.2).
#
# Requires: the backend proxy (WU-1, committed) + a Playwright Chromium browser
# (auto-installed, or present in ~/.cache/ms-playwright/) + outbound network
# to ic0.app (the box reaches it — verified during WU-1).
verify-ic-agent-web:
    #!/usr/bin/env bash
    set -euo pipefail
    probe_dir="{{root}}/scripts/ic_agent_web_probe"
    echo "==> Starting backend API server (for the IC CORS proxy)..."
    just api-dev-up
    api_port=$(just _api-dev-port)
    proxy_host="http://127.0.0.1:${api_port}"
    echo "==> IC proxy at ${proxy_host}/api/v1/ic"
    echo "==> Installing Playwright harness deps (idempotent)..."
    cd "$probe_dir" && npm install --no-audit --no-fund --omit=dev >/dev/null 2>&1
    if ! node -e "require('playwright')" 2>/dev/null; then
      echo "==> Playwright Chromium not found in cache; installing browser..."
      npx playwright install chromium
    fi
    echo "==> Building agent probe web app (flutter build web --target=tool/web_probe_agent_main.dart)..."
    cd {{flutter_dir}} && flutter build web --target=tool/web_probe_agent_main.dart --dart-define=IC_AGENT_PROXY_HOST="${proxy_host}"
    echo "==> Running headless-Chromium agent PoC (foreground, timeout-bounded)..."
    set +e
    timeout 180 node "$probe_dir/verify_agent.js"
    probe_exit=$?
    set -e
    just api-dev-down >/dev/null 2>&1 || true
    if [ "$probe_exit" -ne 0 ]; then echo "❌ IC-agent web probe FAILED (exit $probe_exit)"; exit 1; fi
    echo "✅ IC-agent web probe PASSED"

# =============================================================================
# Integration / E2E (real-app user-flow probes)
# =============================================================================
#
# `test-ux-probe` runs the highest-fidelity suite under
# apps/autorun_flutter/integration_test/ux_probe/. Each probe launches the REAL
# app (lib/main.dart) under the integration-test binding on a 1440x900 Xvfb
# surface, driving interactive flows and asserting widget-tree behavior. They
# need three things the unit/widget tests do not:
#   1. libicp_core.so on LD_LIBRARY_PATH (real FFI: Ed25519 keypair gen,
#      vault encrypt/decrypt, poll-endpoint signing).
#   2. An X display (Xvfb :99) — they render a real surface.
#   3. A working Secret Service for the profile-creating probes. The box has no
#      gnome-keyring, so the suite uses TWO passes with opposite expectations:
#        PASS 1 (keyring-less)  : StorageUnavailable path — wus2_readiness,
#                                 new2_diagnostic, r3_review (WU-S2 panel), etc.
#        PASS 2 (mock keyring)  : StorageReady path — r3_addendum creates REAL
#                                 profiles end-to-end (FFI gen + libsecret);
#                                 f_dapp_vote_flow creates a REAL profile
#                                 mid-flow to sign the headline dapp vote;
#                                 g_first_run_wizard drives the wizard FORM
#                                 happy-path (type name → Get Started → main
#                                 shell reachable) on a real app boot;
#                                 h_vault_lifecycle drives the vault full-UI
#                                 chain (setup → restart → unlock decrypts →
#                                 wrong-pw reject) with REAL FFI crypto through
#                                 the real production screens.
#
# State is isolated: ~/.cache/data/com.example.icp_autorun/ is wiped before
# every file so probes never contaminate each other.
#
# Run the ux_probe real-app user-flow integration suite (Xvfb + FFI + mock keyring)
test-ux-probe:
    #!/usr/bin/env bash
    set -euo pipefail
    RELEASE_LIB="{{root}}/target/release/libicp_core.so"
    STATE_DIR="{{state_dir}}"
    PASS1_LOG="{{logs_dir}}/ux-probe-pass1-keyring-less.log"
    PASS2_LOG="{{logs_dir}}/ux-probe-pass2-mock-keyring.log"
    mkdir -p "{{logs_dir}}"

    echo "==> ux_probe: real-app user-flow integration suite"

    # --- 1. Ensure the FFI library is built (real libicp_core.so) -------------
    if [[ ! -f "$RELEASE_LIB" ]]; then
        echo "==> libicp_core.so missing — building (cargo build --release)..."
        (cd "{{root}}" && cargo build --release)
    fi
    [[ -f "$RELEASE_LIB" ]] || { echo "❌ $RELEASE_LIB not found after build"; exit 1; }
    export LD_LIBRARY_PATH="{{root}}/target/release${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    # --- 2. Ensure Xvfb :99 is up (1440x900 screen, matches kDesktopSize) -----
    XVFB_STARTED=0
    if [[ ! -S /tmp/.X11-unix/X99 ]] || ! pgrep -x Xvfb >/dev/null 2>&1; then
        echo "==> starting Xvfb :99 (1440x900x24 + XTEST)"
        Xvfb :99 -screen 0 1440x900x24 -ac +extension XTEST \
            >"{{logs_dir}}/xvfb-ux-probe.log" 2>&1 &
        XVFB_PID=$!
        XVFB_STARTED=1
        for _ in $(seq 1 30); do
            [[ -S /tmp/.X11-unix/X99 ]] && break
            sleep 0.2
        done
    fi
    [[ -S /tmp/.X11-unix/X99 ]] || { echo "❌ Xvfb :99 did not come up"; exit 1; }
    export DISPLAY=:99
    # Only tear down an Xvfb WE started; never kill a host/session one.
    if [[ "$XVFB_STARTED" -eq 1 ]]; then
        trap 'kill "$XVFB_PID" 2>/dev/null || true' EXIT
    fi

    # --- 3. PASS 1: keyring-less (StorageUnavailable) probes ------------------
    # Fresh per-pass log (NOT append) — avoids the stale-false-positive that
    # bites `flutter-tests`. Pass/fail is decided by each `flutter test` exit
    # code, not by grepping the log.
    NOMOCK=( _smoke_test b_download_test c_explore_test e_profile_menu_test \
             wus2_readiness_test new2_diagnostic_test r3_review_test \
             i_marketplace_download_flow_test )
    : > "$PASS1_LOG"
    echo "==> PASS 1 (keyring-less): ${#NOMOCK[@]} files -> $PASS1_LOG"
    fail1=0
    for t in "${NOMOCK[@]}"; do
        rm -rf "$STATE_DIR" 2>/dev/null || true   # isolate state per file
        printf '   - %-26s ... ' "$t"
        if (cd "{{flutter_dir}}" && flutter test -d linux "integration_test/ux_probe/$t.dart" \
                --reporter=compact --timeout=240s) >>"$PASS1_LOG" 2>&1; then
            echo "OK"
        else
            echo "FAIL  (see $PASS1_LOG)"; fail1=1
        fi
    done

    # --- 4. PASS 2: mock Secret Service (StorageReady) probes -----------------
    # run-with-mock-keyring.sh auto-resolves a python with dbus_next; verify
    # at least one candidate exists before starting the (expensive) mock.
    if ! { python3 -c 'import dbus_next' 2>/dev/null || \
           python3.13 -c 'import dbus_next' 2>/dev/null || \
           /usr/bin/python3.13 -c 'import dbus_next' 2>/dev/null; }; then
        echo "❌ PASS 2 needs python3 + dbus-next (mock Secret Service). Install:"
        echo "   python3.13 -m pip install dbus-next"
        exit 1
    fi
    MOCK=( r3_addendum_test f_dapp_vote_flow_test g_first_run_wizard_happy_path_test h_vault_lifecycle_test )
    : > "$PASS2_LOG"
    echo "==> PASS 2 (mock keyring): ${#MOCK[@]} files -> $PASS2_LOG"
    fail2=0
    for t in "${MOCK[@]}"; do
        rm -rf "$STATE_DIR" 2>/dev/null || true
        printf '   - %-26s ... ' "$t"
        if "{{scripts_dir}}/run-with-mock-keyring.sh" --display :99 -- \
                bash -c 'cd "{{flutter_dir}}" && \
                    LD_LIBRARY_PATH="{{root}}/target/release" \
                    flutter test -d linux "integration_test/ux_probe/'"$t"'.dart" \
                    --reporter=compact --timeout=240s' >>"$PASS2_LOG" 2>&1; then
            echo "OK"
        else
            echo "FAIL  (see $PASS2_LOG)"; fail2=1
        fi
    done

    # --- 5. Verdict -----------------------------------------------------------
    echo ""
    if [[ $fail1 -eq 0 && $fail2 -eq 0 ]]; then
        echo "✅ ux_probe suite PASSED — PASS 1 (keyring-less) + PASS 2 (mock keyring)."
        exit 0
    fi
    echo "❌ ux_probe suite FAILED — see:"
    [[ $fail1 -eq 1 ]] && echo "   $PASS1_LOG"
    [[ $fail2 -eq 1 ]] && echo "   $PASS2_LOG"
    exit 1

# =============================================================================
# Unified E2E Harness (Desktop + Web) — docs/specs/2026-07-15-e2e-harness-and-ux.md
# One flow catalog (integration_test/e2e/flow_catalog.dart) run on BOTH real
# surfaces. Desktop = 2 shared boots (keyring-less + mock-keyring) instead of
# one-per-file → ~2.5x faster than the old ux_probe suite. Flow implementations
# register into a FlowRegistry; the catalog is the single coverage contract.
# =============================================================================

# e2e-desktop: run the unified DESKTOP suites. Two app boots total:
#   PASS 1 (keyring-less) — suite_keyring_less_test.dart   (no Secret Service)
#       includes marketplace + download-history flows (folded from the retired
#       suite_marketplace_test.dart — same backend, same keyring-less surface).
#   PASS 2 (mock keyring)  — suite_mock_keyring_test.dart   (mock Secret Service)
# Each suite boots the REAL app once and runs many phases with resetAppState
# isolation between them.
e2e-desktop:
    #!/usr/bin/env bash
    set -euo pipefail
    RELEASE_LIB="{{root}}/target/release/libicp_core.so"
    STATE_DIR="{{state_dir}}"
    LOG="{{logs_dir}}/e2e-desktop.log"
    mkdir -p "{{logs_dir}}"

    echo "==> e2e-desktop: unified harness (2 shared boots)"

    # --- 1. Real FFI library --------------------------------------------------
    if [[ ! -f "$RELEASE_LIB" ]]; then
        echo "==> libicp_core.so missing — building (cargo build --release)..."
        (cd "{{root}}" && cargo build --release)
    fi
    [[ -f "$RELEASE_LIB" ]] || { echo "❌ $RELEASE_LIB not found"; exit 1; }
    export LD_LIBRARY_PATH="{{root}}/target/release${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    # --- 2. Xvfb :99 (1440x900, matches kDesktopSize) -------------------------
    XVFB_STARTED=0
    if [[ ! -S /tmp/.X11-unix/X99 ]] || ! pgrep -x Xvfb >/dev/null 2>&1; then
        echo "==> starting Xvfb :99"
        Xvfb :99 -screen 0 1440x900x24 -ac +extension XTEST \
            >"{{logs_dir}}/xvfb-e2e.log" 2>&1 &
        XVFB_PID=$!; XVFB_STARTED=1
        for _ in $(seq 1 30); do [[ -S /tmp/.X11-unix/X99 ]] && break; sleep 0.2; done
    fi
    [[ -S /tmp/.X11-unix/X99 ]] || { echo "❌ Xvfb :99 did not come up"; exit 1; }
    export DISPLAY=:99
    if [[ "$XVFB_STARTED" -eq 1 ]]; then trap 'kill "$XVFB_PID" 2>/dev/null || true' EXIT; fi

    # Drive the REAL app against the REAL local backend (kDebugMode desktop
    # honors MARKETPLACE_API_PORT → http://127.0.0.1:port). Fails loud if down.
    export MARKETPLACE_API_PORT=$(just _api-dev-port)
    echo "==> backend: http://127.0.0.1:$MARKETPLACE_API_PORT"

    # --- 3. PASS 1: keyring-less (one boot) -----------------------------------
    : > "$LOG"
    rm -rf "$STATE_DIR" 2>/dev/null || true
    echo "==> PASS 1 (keyring-less): suite_keyring_less_test.dart"
    if (cd "{{flutter_dir}}" && flutter test -d linux \
            integration_test/e2e/suite_keyring_less_test.dart \
            --reporter=compact --timeout=240s) >>"$LOG" 2>&1; then
        echo "   PASS 1 OK"
    else
        echo "   PASS 1 FAIL  (see $LOG)"; exit 1
    fi

    # --- 4. PASS 2: mock Secret Service (one boot) ----------------------------
    rm -rf "$STATE_DIR" 2>/dev/null || true
    echo "==> PASS 2 (mock keyring): suite_mock_keyring_test.dart"
    if "{{scripts_dir}}/run-with-mock-keyring.sh" --display :99 -- \
            bash -c 'cd "{{flutter_dir}}" && \
                LD_LIBRARY_PATH="{{root}}/target/release" \
                flutter test -d linux integration_test/e2e/suite_mock_keyring_test.dart \
                    --reporter=compact --timeout=240s' >>"$LOG" 2>&1; then
        echo "   PASS 2 OK"
    else
        echo "   PASS 2 FAIL  (see $LOG)"; exit 1
    fi

    echo "✅ e2e-desktop PASSED — all suites green (2 boots). Log: $LOG"

# e2e-fast: run a SINGLE suite file for a sub-minute dev loop (default: the
# keyring-less smoke, no mock-keyring wrap needed). Pass a file path to target
# another suite.
e2e-fast file="integration_test/e2e/suite_keyring_less_test.dart":
    #!/usr/bin/env bash
    set -euo pipefail
    RELEASE_LIB="{{root}}/target/release/libicp_core.so"
    [[ -f "$RELEASE_LIB" ]] || { echo "❌ build first: cargo build --release"; exit 1; }
    export LD_LIBRARY_PATH="{{root}}/target/release"
    if [[ ! -S /tmp/.X11-unix/X99 ]] || ! pgrep -x Xvfb >/dev/null 2>&1; then
        Xvfb :99 -screen 0 1440x900x24 -ac >/dev/null 2>&1 &
        for _ in $(seq 1 30); do [[ -S /tmp/.X11-unix/X99 ]] && break; sleep 0.2; done
    fi
    export DISPLAY=:99
    rm -rf "{{state_dir}}" 2>/dev/null || true
    # Drive the REAL app against the REAL local backend (kDebugMode desktop
    # honors MARKETPLACE_API_PORT → http://127.0.0.1:port). Without it the app
    # falls back to the production host and marketplace fetches throw 530.
    export MARKETPLACE_API_PORT=$(just _api-dev-port)
    echo "==> e2e-fast: {{file}} (backend :$MARKETPLACE_API_PORT)"
    cd "{{flutter_dir}}" && flutter test -d linux "{{file}}" --reporter=compact --timeout=240s

# e2e-one: run a keyring-less or mock-keyring suite UP TO a specific flow for
# fast single-flow iteration. The suite boots the real app, runs all setup
# phases, then stops immediately after the requested flow.
# Usage: just e2e-one <flow-id> [suite]
#   suite: keyring-less (default, includes marketplace), mock-keyring
# Example: just e2e-one scripts.search
#          just e2e-one settings.theme
#          just e2e-one vault.setup mock-keyring
e2e-one flow suite="keyring-less":
    #!/usr/bin/env bash
    set -euo pipefail
    RELEASE_LIB="{{root}}/target/release/libicp_core.so"
    [[ -f "$RELEASE_LIB" ]] || { echo "❌ build first: cargo build --release"; exit 1; }
    export LD_LIBRARY_PATH="{{root}}/target/release"

    case "{{suite}}" in
        keyring-less)  FILE="suite_keyring_less_test.dart" ;;
        mock-keyring)  FILE="suite_mock_keyring_test.dart" ;;
        *) echo "❌ Unknown suite '{{suite}}'. Use: keyring-less, mock-keyring"; exit 1 ;;
    esac

    if [[ "{{suite}}" == "mock-keyring" ]]; then
        export MARKETPLACE_API_PORT=$(just _api-dev-port)
        export DISPLAY=:99
        scripts/run-with-mock-keyring.sh --display :99 -- bash -c \
          'cd "{{flutter_dir}}" && flutter test -d linux \
          integration_test/e2e/'"$FILE"' \
          --dart-define=ICP_E2E_STOP_AFTER={{flow}} \
          --reporter=compact --timeout=300s'
        exit 0
    fi

    if [[ ! -S /tmp/.X11-unix/X99 ]] || ! pgrep -x Xvfb >/dev/null 2>&1; then
        Xvfb :99 -screen 0 1440x900x24 -ac >/dev/null 2>&1 &
        for _ in $(seq 1 30); do [[ -S /tmp/.X11-unix/X99 ]] && break; sleep 0.2; done
    fi
    export DISPLAY=:99
    rm -rf "{{state_dir}}" 2>/dev/null || true
    export MARKETPLACE_API_PORT=$(just _api-dev-port)
    echo "==> e2e-one: {{suite}} stop-after={{flow}} (backend :$MARKETPLACE_API_PORT)"
    cd "{{flutter_dir}}" && flutter test -d linux "integration_test/e2e/$FILE" \
      --dart-define=ICP_E2E_STOP_AFTER={{flow}} --reporter=compact --timeout=240s


# e2e-keyring-unavailable: run the `first_run.keyring_unavailable` flow
# under scripts/run-without-keyring.sh — a wrapper that kills any running
# gnome-keyring-daemon + blanks DBUS_SESSION_BUS_ADDRESS so the
# SecureStorageReadiness probe in the app returns StorageUnavailable and the
# wizard renders the WU-S2 actionable blocking panel
# (LinuxSecretServiceHelp). On a keyring-less box (no gnome-keyring installed)
# the wrapper is a near-no-op and the flow passes naturally. On a box WITH
# gnome-keyring auto-starting, the wrapper DISABLES it for this run so the
# panel is exercised. The wrapper fails loud if the Secret Service is still
# reachable after kill + env-wipe.
e2e-keyring-unavailable:
    #!/usr/bin/env bash
    set -euo pipefail
    RELEASE_LIB="{{root}}/target/release/libicp_core.so"
    [[ -f "$RELEASE_LIB" ]] || { echo "❌ build first: cargo build --release"; exit 1; }
    if [[ ! -S /tmp/.X11-unix/X99 ]] || ! pgrep -x Xvfb >/dev/null 2>&1; then
        Xvfb :99 -screen 0 1440x900x24 -ac >/dev/null 2>&1 &
        for _ in $(seq 1 30); do [[ -S /tmp/.X11-unix/X99 ]] && break; sleep 0.2; done
    fi
    export DISPLAY=:99
    rm -rf "{{state_dir}}" 2>/dev/null || true
    export MARKETPLACE_API_PORT=$(just _api-dev-port)
    echo "==> e2e-keyring-unavailable: first_run.keyring_unavailable (backend :$MARKETPLACE_API_PORT)"
    echo "    wrapping with scripts/run-without-keyring.sh to force the StorageUnavailable path"
    "{{scripts_dir}}/run-without-keyring.sh" -- bash -c \
      'cd "{{flutter_dir}}" && LD_LIBRARY_PATH="{{root}}/target/release" \
       flutter test -d linux integration_test/e2e/suite_keyring_less_test.dart \
       --dart-define=ICP_E2E_STOP_AFTER=first_run.keyring_unavailable \
       --reporter=compact --timeout=240s'


# e2e-web: REAL app on Web as widget tests via `flutter test -d chrome`
# (headless, no chromedriver, ~5s warm). The conditional-import split selects
# native_bridge_web.dart (real pure-Dart Ed25519/secp256k1/Argon2id/AES-GCM),
# so NO FFI is touched. Covers all Surface.web / Surface.both flows; QuickJS /
# IC-agent / deeplink / keyboard-shortcut flows are desktop-only.
#
# Two suite files run by default:
#   1. suite_web_smoke_test.dart  — Tier 1 (no substrate): boot contract +
#      nav-bar shell render (2 widget tests, no plugins).
#   2. suite_web_flows_test.dart  — Tier A (substrate fakes at the smallest
#      I/O boundary — HTTP, SharedPreferences, FlutterSecureStorage,
#      path_provider, package_info_plus): 7 real-app FlowCatalog flows
#      (first_run.dismiss_wizard, profile.open_menu, settings.open/theme/
#      version_display, scripts.browse_marketplace). Same flow bodies the
#      desktop suite uses (cross-surface sharing via flow_implementations.dart).
#
# Backend is the REAL local server; IC mainnet reaches the browser directly /
# via the CORS proxy. Only ICPay checkout is mocked (ICP_E2E_MOCK_ICPAY=1 —
# icpay.org is unreachable from the sandbox).
#
# Override the suite by passing `file=` (single file):
#   just e2e-web                       # default: both suites
#   just e2e-web file=test/e2e_web/substrate_smoke_test.dart
e2e-web file="test/e2e_web/suite_web_smoke_test.dart test/e2e_web/suite_web_flows_test.dart":
    #!/usr/bin/env bash
    set -euo pipefail
    api_port=$(just _api-dev-port)
    # Resolve a Chromium for `flutter test -d chrome`. Honor $CHROME_EXECUTABLE,
    # else glob the Playwright cache, else install Playwright Chromium.
    if [[ -z "${CHROME_EXECUTABLE:-}" ]]; then
        bin=$(find "$HOME/.cache/ms-playwright" -type f -name chrome \
            -path "*/chrome-linux64/*" 2>/dev/null | sort -V | tail -1 || true)
        if [[ -z "$bin" ]]; then
            echo "==> No Chromium in Playwright cache; installing..."
            cd "{{flutter_dir}}" && npx playwright install chromium >/dev/null
            bin=$(find "$HOME/.cache/ms-playwright" -type f -name chrome \
                -path "*/chrome-linux64/*" 2>/dev/null | sort -V | tail -1)
        fi
        export CHROME_EXECUTABLE="$bin"
    fi
    echo "==> e2e-web: {{file}} (Chromium: $CHROME_EXECUTABLE, backend :$api_port)"
    cd "{{flutter_dir}}" && CHROME_EXECUTABLE="$CHROME_EXECUTABLE" \
        flutter test -d chrome \
        --dart-define=PUBLIC_API_ENDPOINT=http://127.0.0.1:$api_port \
        --dart-define=ICP_E2E=1 \
        --dart-define=ICP_E2E_MOCK_ICPAY=1 \
        {{file}} --reporter=compact --timeout=240s

# e2e-web-playwright: Tier B — Playwright against the BUILT Flutter Web bundle
# (real canvaskit + all Web platform code paths). Two specs:
#   1. bundle boots → flt-glass-pane shadow-root canvas paints (geometry check).
#   2. first-run wizard renders (screenshot artifact; vision-assert separately
#      via `zai-vision_analyze_image` — DOM assertions unavailable, see
#      docs/OPEN_ISSUES.md #WEB-1).
#
# Boots its own static HTTP server on :8099; tear down via trap on exit. The
# bundle MUST be pre-built (call `just web-dev-build` first or this target
# will offer to build it).
#
# Run:
#   just e2e-web-playwright                # build (if needed) + run
#   just e2e-web-playwright --no-build     # skip build (assume bundle exists)
e2e-web-playwright skipbuild="":
    #!/usr/bin/env bash
    set -euo pipefail
    BUNDLE="{{flutter_dir}}/build/web"
    if [[ "{{skipbuild}}" != "--no-build" && ! -f "$BUNDLE/index.html" ]]; then
        echo "==> Bundle missing; building via scripts/web-e2e-build.sh"
        bash "{{root}}/scripts/web-e2e-build.sh"
    elif [[ "{{skipbuild}}" != "--no-build" ]]; then
        # Always rebuild unless explicitly skipped — keeps the bundle in sync
        # with current source.
        echo "==> Building fresh bundle"
        bash "{{root}}/scripts/web-e2e-build.sh"
    fi
    [[ -f "$BUNDLE/index.html" ]] || { echo "❌ $BUNDLE/index.html missing"; exit 1; }

    PW_DIR="{{flutter_dir}}/web_e2e_playwright"
    [[ -d "$PW_DIR/node_modules" ]] || (cd "$PW_DIR" && npm install)
    [[ -d "$HOME/.cache/ms-playwright/chromium"* ]] || \
        (cd "$PW_DIR" && npx playwright install chromium)

    # Serve the bundle on :8099; trap to kill on exit.
    HTTP_PID=""
    cleanup() {
        [[ -n "$HTTP_PID" ]] && kill "$HTTP_PID" 2>/dev/null || true
        wait "$HTTP_PID" 2>/dev/null || true
    }
    trap cleanup EXIT
    echo "==> Serving bundle on http://127.0.0.1:8099"
    (cd "$BUNDLE" && python3 -m http.server 8099) &
    HTTP_PID=$!
    for _ in $(seq 1 30); do
        curl -sf http://127.0.0.1:8099/ >/dev/null && break
        sleep 0.2
    done

    echo "==> Running Playwright"
    cd "$PW_DIR" && npx playwright test --reporter=list --workers=1

# e2e: BOTH surfaces (desktop then web). The full real-app e2e contract.
e2e: e2e-desktop e2e-web
    @echo "✅ e2e PASSED — desktop + web surfaces green"

# =============================================================================
# Development API Server (Local Cargo-based)
# =============================================================================

# Helper to get API port with error checking
_api-dev-port:
    @if [ ! -f "{{api_port_file}}" ]; then echo "❌ API server not running" >&2; exit 1; fi; cat "{{api_port_file}}"

# Start local development API server in background (port=0 for auto-assign)
api-dev-up port="0":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Starting ICP Marketplace API server"
    mkdir -p "{{tmp_dir}}"

    # Check if already running
    if [ -f "{{api_pid_file}}" ]; then
        pid=$(cat "{{api_pid_file}}")
        if kill -0 "$pid" 2>/dev/null; then
            if [ -f "{{api_port_file}}" ]; then
                api_port=$(cat "{{api_port_file}}")
                echo "==> API server already running with PID $pid on port $api_port"
                exit 0
            else
                echo "==> Warning: PID file exists but port file missing, cleaning up..."
                rm -f "{{api_pid_file}}"
            fi
        else
            echo "==> Cleaning up stale PID file..."
            rm -f "{{api_pid_file}}" "{{api_port_file}}"
        fi
    fi

    # Build in the foreground first: a cold compile of the backend takes far
    # longer than the startup-wait timeout below, and compiling here surfaces
    # build errors directly instead of as a silent "failed to start".
    cd {{api_dir}} && cargo build --release
    # Start server in background (run is near-instant now that the build is cached)
    PORT={{port}} cargo run --release > {{logs_dir}}/api-server.log 2>&1 &
    echo $! > {{api_pid_file}}

    # Wait for server to start and extract port from logs
    echo "==> Waiting for API server to start..."
    timeout=30
    for ((i=0; i<timeout; i++)); do
        if [ -f "{{logs_dir}}/api-server.log" ]; then
            api_port=$(grep -aoP 'listening.*?(\[::\]|127\.0\.0\.1|0\.0\.0\.0):\K\d+' {{logs_dir}}/api-server.log | tail -1 || true)
            if [ -n "$api_port" ]; then
                echo "$api_port" > {{api_port_file}}
                export MARKETPLACE_API_PORT="$api_port"
                if timeout 5 curl -s "http://127.0.0.1:$api_port/api/v1/health" >/dev/null 2>&1; then
                    echo "==> ✅ API server is healthy and ready!"
                    echo "==> API Endpoint: http://127.0.0.1:$api_port"
                    echo "==> Health Check: http://127.0.0.1:$api_port/api/v1/health"
                    echo "==> Server logs: {{logs_dir}}/api-server.log"
                    echo "export MARKETPLACE_API_PORT=$api_port" > {{tmp_dir}}/api-env.sh
                    exit 0
                fi
            fi
        fi
        sleep 1
    done
    echo "==> ❌ API server failed to start within $timeout seconds"
    echo "==> Check logs at: {{logs_dir}}/api-server.log"
    # Cleanup on failure
    if [ -f "{{api_pid_file}}" ]; then
        kill -TERM $(cat "{{api_pid_file}}") 2>/dev/null || true
        rm -f "{{api_pid_file}}" "{{api_port_file}}"
    fi
    exit 1

# Stop local development API server
api-dev-down:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Stopping API server"

    # Kill processes by port
    if [ -f "{{api_port_file}}" ]; then
        api_port=$(cat "{{api_port_file}}")
        pids=$(lsof -ti:$api_port 2>/dev/null || true)
        if [ -n "$pids" ]; then
            for pid in $pids; do
                echo "==> Cleaning up process $pid on port $api_port"
                kill -TERM "$pid" 2>/dev/null || true
                sleep 1
                kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
            done
        fi
    fi

    # Kill by PID file
    if [ -f "{{api_pid_file}}" ]; then
        pid=$(cat "{{api_pid_file}}")
        if kill -0 "$pid" 2>/dev/null; then
            echo "==> Stopping API server wrapper with PID $pid"
            pkill -P "$pid" 2>/dev/null || true
            sleep 1
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
            echo "==> ✅ API server stopped"
        fi
    fi

    rm -f "{{api_pid_file}}" "{{api_port_file}}"

# Restart local development API server
api-dev-restart: api-dev-down api-dev-up

# Show local development API server logs
api-dev-logs:
    @tail -f {{logs_dir}}/api-server.log

# Run local development API server in foreground (for debugging)
api-dev:
    @echo "==> Starting API server in development mode"
    cd {{api_dir}} && cargo run

# Build API server in release mode
api-dev-build:
    @echo "==> Building API server (release mode)"
    cd {{api_dir}} && cargo build --release
    @echo "==> ✅ API server built successfully"

# Test local development API endpoints
api-dev-test:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Testing API endpoints"
    api_port=$(just _api-dev-port)
    JQ_CMD=$(command -v jq >/dev/null 2>&1 && echo "jq ." || echo "cat")
    [ "$JQ_CMD" = "cat" ] && echo "==> Note: jq not installed, showing raw JSON"

    echo "==> Testing health endpoint..."
    curl -s "http://127.0.0.1:$api_port/api/v1/health" | $JQ_CMD && echo "✅ Health check passed"

    echo "==> Testing marketplace stats..."
    curl -s "http://127.0.0.1:$api_port/api/v1/marketplace-stats" | $JQ_CMD && echo "✅ Stats endpoint passed"

    echo "==> Testing scripts listing..."
    curl -s "http://127.0.0.1:$api_port/api/v1/scripts" | $JQ_CMD && echo "✅ Scripts listing passed"

    echo "==> ✅ All endpoint tests completed"

# Reset local development API database
api-dev-reset:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Resetting API database"
    api_port=$(just _api-dev-port)
    JQ_CMD=$(command -v jq >/dev/null 2>&1 && echo "jq ." || echo "cat")
    curl -X POST -s "http://127.0.0.1:$api_port/api/dev/reset-database" | $JQ_CMD

# =============================================================================
# Flutter Development
# =============================================================================

# Run Flutter app with local development API server
flutter-dev-local +args="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Starting Flutter app with local API server"
    api_port=$(just _api-dev-port)
    echo "==> Using API endpoint: http://127.0.0.1:$api_port"
    cd {{flutter_dir}} && flutter run -d linux --dart-define=PUBLIC_API_ENDPOINT=http://127.0.0.1:$api_port {{args}}

# Build the Flutter WEB app against the local dev backend. The app's compiled-in
# default endpoint (PUBLIC_API_ENDPOINT) points at the production host, which is
# unreachable from a dev box — and Web has no Platform.environment to pick up
# MARKETPLACE_API_PORT at runtime. So a plain `flutter build web` silently talks
# to a dead host. This target injects the live local backend via dart-define so
# the built bundle works against `just api-dev-up` without remembering any flag.
web-dev-build:
    #!/usr/bin/env bash
    set -euo pipefail
    api_port=$(just _api-dev-port)
    echo "==> Building Flutter Web against local backend http://127.0.0.1:$api_port"
    cd {{flutter_dir}} && flutter build web --dart-define=PUBLIC_API_ENDPOINT=http://127.0.0.1:$api_port

# Serve the built Flutter Web app on a fixed local port (default 8099) so a
# browser/UX-reviewer can reach it deterministically. Re-serves an existing
# build; pair with `web-dev-build` (or use `web-dev`) for a fresh bundle.
web-dev-serve port="8099":
    @echo "==> Serving Flutter Web at http://127.0.0.1:{{port}}/ (Ctrl-C to stop)"
    @echo "==> Backend: http://127.0.0.1:$(just _api-dev-port)"
    @cd {{flutter_dir}} && python3 -m http.server {{port}} --bind 127.0.0.1 --directory build/web

# Build + serve the Flutter Web app against the local dev backend (one-shot).
web-dev: web-dev-build
    @just web-dev-serve

# Start Android emulator
android-emulator:
    @echo "==> Starting Android emulator..."
    {{scripts_dir}}/run_android_emulator.sh

# =============================================================================
# Docker Deployment
# =============================================================================

# Deploy to production with Docker Compose and Cloudflare Tunnel
docker-deploy-prod:
    @echo "==> Deploying to PRODUCTION with Docker Compose + Cloudflare Tunnel"
    cargo build --release
    cd {{api_dir}} && ./scripts/start-tunnel.sh

# Deploy to local development (no tunnel)
docker-deploy-dev:
    @echo "==> Deploying to DEVELOPMENT (local only)"
    cargo build --release
    cd {{api_dir}} && ./scripts/start-dev.sh

# Start production Docker containers
docker-prod-up:
    @echo "==> Starting production Docker containers"
    cd {{api_dir}} && export $(cat .env | xargs) && {{compose_prod}} up -d

# Start development Docker containers
docker-dev-up:
    @echo "==> Starting development Docker containers"
    cd {{api_dir}} && {{compose_dev}} up -d

# Stop production Docker containers
docker-prod-down:
    @echo "==> Stopping production Docker containers"
    cd {{api_dir}} && {{compose_prod}} down

# Stop development Docker containers
docker-dev-down:
    @echo "==> Stopping development Docker containers"
    cd {{api_dir}} && {{compose_dev}} down

# Stop all Docker containers (both prod and dev)
docker-all-down:
    @echo "==> Stopping all Docker containers"
    cd {{api_dir}} && {{compose_prod}} down 2>/dev/null || true
    cd {{api_dir}} && {{compose_dev}} down 2>/dev/null || true

# View production Docker logs
docker-prod-logs:
    @echo "==> Viewing production Docker logs (Ctrl+C to stop)"
    cd {{api_dir}} && {{compose_prod}} logs -f

# View development Docker logs
docker-dev-logs:
    @echo "==> Viewing development Docker logs (Ctrl+C to stop)"
    cd {{api_dir}} && {{compose_dev}} logs -f

# Check production Docker container status
docker-prod-status:
    @echo "==> Production Docker container status"
    cd {{api_dir}} && {{compose_prod}} ps

# Check development Docker container status
docker-dev-status:
    @echo "==> Development Docker container status"
    cd {{api_dir}} && {{compose_dev}} ps

# Check all Docker container status (both prod and dev)
docker-all-status:
    @echo "==> Production:"
    cd {{api_dir}} && {{compose_prod}} ps
    @echo ""
    @echo "==> Development:"
    cd {{api_dir}} && {{compose_dev}} ps

# Rebuild and restart production Docker containers
docker-prod-rebuild:
    @echo "==> Rebuilding and restarting production Docker containers"
    cd {{api_dir}} && export $(cat .env | xargs) && {{compose_prod}} up -d --build

# Rebuild and restart development Docker containers
docker-dev-rebuild:
    @echo "==> Rebuilding and restarting development Docker containers"
    cd {{api_dir}} && {{compose_dev}} up -d --build

# =============================================================================
# Maintenance
# =============================================================================

# Clean build artifacts
clean:
    @echo "==> Cleaning build artifacts..."
    rm -rf {{flutter_dir}}/android/app/src/main/jniLibs/* || true
    rm -rf {{flutter_dir}}/build || true
    rm -rf {{flutter_dir}}/linux/flutter/ephemeral || true
    rm -rf {{api_dir}}/target/debug || true

# Remove transient tool/runtime scratch directories (.tmp/, .just-tmp/)
clean-tmp:
    @echo "==> Cleaning scratch directories..."
    rm -rf {{root}}/.tmp || true
    rm -rf {{root}}/.just-tmp || true

# Deep clean including dependencies
distclean: clean
    @echo "==> Deep cleaning all artifacts and dependencies..."
    rm -rf {{root}}/target || true
    rm -rf {{flutter_dir}}/.dart_tool || true
    rm -rf {{flutter_dir}}/.gradle || true
    rm -rf {{api_dir}}/target || true
