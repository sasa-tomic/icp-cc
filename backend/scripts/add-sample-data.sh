#!/bin/bash

# Add sample data to SQLite database for development.
#
# UXR5-1: every bundle here is a REAL TypeScript/QuickJS contract bundle
# (mirrors the examples in apps/autorun_flutter/lib/examples/). The runtime is
# TS-only — Lua bundles are stale and cannot execute, so none ship here. Each
# bundle is content-detected as "typescript" by backend ScriptLanguage::detect.
#
# Idempotent: the script DELETEs then INSERTs, so re-running is safe.

set -e

echo "📝 Adding sample data to SQLite database..."

export DATABASE_URL="sqlite:./data/marketplace-dev.db"

# Check if database exists
if [ ! -f "./data/marketplace-dev.db" ]; then
    echo "❌ Database file not found. Run ./scripts/dev-setup.sh first."
    exit 1
fi

# Add sample scripts. Bundle strings use REAL newlines (multi-line SQL strings)
# and double-quote-only JS so they need no single-quote escaping.
sqlite3 ./data/marketplace-dev.db << 'EOF'
-- Clear existing data (idempotent: re-running the seed is safe).
DELETE FROM reviews;
DELETE FROM scripts;
DELETE FROM account_public_keys;
DELETE FROM accounts;

-- Sample accounts
INSERT INTO accounts (
    id, username, display_name, created_at, updated_at
) VALUES
(
    'account-alice',
    'alice',
    'Alice Developer',
    datetime('now', '-30 days'),
    datetime('now', '-30 days')
),
(
    'account-bob',
    'bob',
    'Bob Coder',
    datetime('now', '-20 days'),
    datetime('now', '-20 days')
),
(
    'account-gamedev',
    'gamedev',
    'GameDev Pro',
    datetime('now', '-15 days'),
    datetime('now', '-15 days')
);

-- Sample scripts — curated TypeScript/QuickJS contract bundles.
INSERT INTO scripts (
    id, slug, owner_account_id, title, description, category, tags, bundle,
    author_principal, author_public_key, upload_signature, canister_ids, icon_url,
    screenshots, version, compatibility, price, is_public, downloads, rating,
    review_count, created_at, updated_at
) VALUES
(
    'hello-ic-starter',
    'hello-ic-starter',
    'account-alice',
    'Hello IC Starter',
    'A minimal starter: greeting, counter, and text field. The canonical first ICP script — mirrors examples/01_hello_world.js.',
    'utility',
    '["hello", "starter", "beginner", "counter"]',
    '// Minimal TypeScript/QuickJS bundle: a greeting + counter.
// Contract: expose globalThis.init / view / update.
"use strict";
(() => {
  function init() {
    return { state: { count: 0, name: "" }, effects: [] };
  }

  function view(state) {
    var count = state.count || 0;
    var name = typeof state.name === "string" ? state.name : "";
    var greeting = name.length > 0 ? "Hello, " + name + "!" : "Hello, IC!";
    return {
      type: "column",
      children: [
        { type: "text", props: { text: greeting } },
        { type: "text", props: { text: "Count: " + count } },
        {
          type: "row",
          children: [
            { type: "button", props: { label: "Increment", on_press: { type: "inc" } } },
            { type: "button", props: { label: "Reset", on_press: { type: "reset" } } }
          ]
        },
        {
          type: "text_field",
          props: { label: "Your name", placeholder: "Enter your name", value: name, on_change: { type: "set_name" } }
        }
      ]
    };
  }

  function update(msg, state) {
    var t = (msg && msg.type) || "";
    if (t === "inc") { return { state: { ...state, count: (state.count || 0) + 1 }, effects: [] }; }
    if (t === "reset") { return { state: { ...state, count: 0 }, effects: [] }; }
    if (t === "set_name") { return { state: { ...state, name: typeof msg.value === "string" ? msg.value : "" }, effects: [] }; }
    return { state: state, effects: [] };
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();',
    '2vxsx-fae',
    'test-public-key-alice',
    'test-signature-hello-ic',
    '["rrkah-fqaaa-aaaaa-aaaaq-cai"]',
    'https://picsum.photos/seed/hello/100/100.jpg',
    '["https://picsum.photos/seed/hello1/300/200.jpg", "https://picsum.photos/seed/hello2/300/200.jpg"]',
    '1.0.0',
    'All ICP Canisters',
    0.0,
    1,
    42,
    4.5,
    3,
    datetime('now', '-7 days'),
    datetime('now', '-7 days')
),
(
    'icp-balance-reader',
    'icp-balance-reader',
    'account-bob',
    'ICP Balance Reader',
    'Query the ICP ledger canister and display a formatted balance. Demonstrates the effect flow: update() emits an icp_call, the host executes it, then delivers the result — mirrors examples/02_canister_query.js.',
    'data-processing',
    '["icp", "ledger", "balance", "canister"]',
    '// TypeScript/QuickJS bundle: query an ICP canister and format the result.
// Demonstrates the effect flow (icp_call -> effect/result).
"use strict";
(() => {
  var LEDGER = "ryjl3-tyaaa-aaaaa-aaaba-cai";

  function init() {
    return { state: { loading: false, balanceE8s: null, error: "" }, effects: [] };
  }

  function view(state) {
    var children = [];
    children.push({ type: "text", props: { text: "ICP Ledger balance lookup" } });
    children.push({ type: "button", props: { label: state.loading ? "Loading..." : "Fetch balance", on_press: { type: "fetch" } } });
    if (state.error && state.error.length > 0) {
      children.push({ type: "text", props: { text: "Error: " + state.error } });
    }
    if (state.balanceE8s !== null && state.balanceE8s !== undefined) {
      var formatted = icp_format_icp(state.balanceE8s, 8);
      children.push({ type: "section", props: { title: "Balance", content: formatted + " ICP (" + state.balanceE8s + " e8s)" } });
    }
    return { type: "column", children: children };
  }

  function update(msg, state) {
    var t = (msg && msg.type) || "";
    if (t === "fetch") {
      var effect = { kind: "icp_call", id: "balance", mode: 0, canister_id: LEDGER, method: "account_balance", args: "{\"account\":[]}" };
      return { state: { ...state, loading: true, error: "" }, effects: [effect] };
    }
    if (t === "effect/result" && msg.id === "balance") {
      if (msg.ok) {
        var e8s = readE8s(msg.data);
        return { state: { loading: false, balanceE8s: e8s, error: "" }, effects: [] };
      }
      return { state: { loading: false, balanceE8s: null, error: String(msg.error || "unknown error") }, effects: [] };
    }
    return { state: state, effects: [] };
  }

  function readE8s(data) {
    if (data === null || data === undefined) return 0;
    if (typeof data === "number") return data;
    if (typeof data === "object") {
      if (typeof data.e8s === "number") return data.e8s;
      if (Array.isArray(data)) return data.length;
    }
    return 0;
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();',
    '3v5f3-hae',
    'test-public-key-bob',
    'test-signature-icp-balance',
    '["ryjl3-tyaaa-aaaaa-aaaba-cai"]',
    'https://picsum.photos/seed/balance/100/100.jpg',
    '["https://picsum.photos/seed/balance1/300/200.jpg"]',
    '1.2.0',
    'ICP Ledger',
    1.99,
    1,
    128,
    4.8,
    12,
    datetime('now', '-3 days'),
    datetime('now', '-1 day')
),
(
    'interactive-counter',
    'interactive-counter',
    'account-gamedev',
    'Interactive Counter',
    'A stateful counter with increment and reset. The simplest end-to-end demonstration of the init/view/update contract — mirrors examples/05_typescript_counter.js.',
    'utility',
    '["counter", "state", "interactive", "demo"]',
    '// TypeScript/QuickJS bundle: a stateful counter.
"use strict";
(() => {
  function init() {
    return { state: { count: 0 }, effects: [] };
  }

  function view(state) {
    return {
      type: "column",
      children: [
        { type: "text", props: { text: "Count: " + (state.count || 0) } },
        { type: "button", props: { label: "Increment", on_press: { type: "inc" } } },
        { type: "button", props: { label: "Reset", on_press: { type: "reset" } } }
      ]
    };
  }

  function update(msg, state) {
    if (msg.type === "inc") {
      return { state: { count: (state.count || 0) + 1 }, effects: [] };
    }
    if (msg.type === "reset") {
      return { state: { count: 0 }, effects: [] };
    }
    return { state: state, effects: [] };
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();',
    '4w5t6-yae',
    'test-public-key-gamedev',
    'test-signature-counter',
    '["ryjl3-tyaaa-aaaaa-aaaba-cai"]',
    'https://picsum.photos/seed/counter/100/100.jpg',
    '["https://picsum.photos/seed/counter1/300/200.jpg", "https://picsum.photos/seed/counter2/300/200.jpg"]',
    '1.0.0',
    'All ICP Canisters',
    4.99,
    1,
    256,
    4.2,
    8,
    datetime('now', '-1 day'),
    datetime('now', '-12 hours')
);

-- Sample reviews
INSERT INTO reviews (
    id, script_id, user_id, rating, comment, created_at, updated_at
) VALUES
(
    'review-001',
    'hello-ic-starter',
    'user-alpha',
    5,
    'Perfect for beginners! Very clear and well-documented.',
    datetime('now', '-6 days'),
    datetime('now', '-6 days')
),
(
    'review-002',
    'hello-ic-starter',
    'user-beta',
    4,
    'Great starting point. Would love to see more examples.',
    datetime('now', '-5 days'),
    datetime('now', '-5 days')
),
(
    'review-003',
    'icp-balance-reader',
    'user-gamma',
    5,
    'Excellent ledger demo. Saved me hours of wiring effects by hand!',
    datetime('now', '-2 days'),
    datetime('now', '-2 days')
),
(
    'review-004',
    'icp-balance-reader',
    'user-delta',
    4,
    'Works well. A canister-call cheatsheet would be a nice addition.',
    datetime('now', '-1 day'),
    datetime('now', '-1 day')
),
(
    'review-005',
    'interactive-counter',
    'user-epsilon',
    5,
    'Exactly what I needed to understand the init/view/update contract!',
    datetime('now', '-10 hours'),
    datetime('now', '-10 hours')
);

EOF

echo "✅ Sample data added successfully!"
echo ""
echo "📊 Added:"
echo "  • 3 TypeScript/QuickJS contract bundles (content-detected as typescript)"
echo "  • 5 sample reviews"
echo "  • Ratings between 4-5 stars"
echo ""
echo "🌐 Test the API:"
echo "  curl http://localhost:58000/api/v1/scripts"
echo "  curl http://localhost:58000/api/v1/scripts/hello-ic-starter/preview"
