# UX Review — Round 6 (Wave-3 LIVE verification)

**Date:** 2026-07-09
**Reviewer work unit:** UX-Round6 — a **LIVE verification** of the seven
Wave-3 fixes that landed after [Round 5](2026-07-08-ux-review.md)
(UXR5-1 … UXR5-7), plus a premium-quality sweep for new residual friction.
**Baseline:** [Round 5](2026-07-08-ux-review.md) (which found the seven issues
and proposed these fixes). Wave-3 commit list:
`git log --oneline 880351ee^..04867890` (commits `880351ee` … `04867890`).

---

## Method (and an honesty note about the reviewer model)

Every Wave-3 item was driven **as a real user against a real, seeded backend** —
not by code review. Two complementary live techniques (neither mocks product
behaviour; the only mock is the sanctioned Secret Service stand-in):

1. **Flutter integration probes** (in `/tmp/opencode/probe_round6/`, **outside**
   the repo so `lib/`/`test/` are untouched) that pump the **production**
   `ScriptDetailsDialog` / `UnifiedSetupWizard` / `AccountProfileScreen` against
   the **real** `MarketplaceOpenApiService` hitting the **real** local backend
   (`just api-dev-up` → seeded via `backend/scripts/add-sample-data.sh`). They
   print authoritative **visible-text dumps** (the primary evidence) and capture
   render-tree screenshots. This is the most reliable way to get authoritative
   text headlessly and is the same discipline Round-4/5 used.
2. **Live GTK release binary** under Xvfb `:99` (1440×900×24) +
   `scripts/run-with-mock-keyring.sh`, captured with ImageMagick
   `import -window root`. Proves the app truly runs on this box (rebuilt first,
   per the Round-5 lesson about stale binaries).

> **Reviewer constraint (honesty):** this model **cannot view images** (the
> `Read` tool rejects image input). The screenshots in
> [`ux_screenshots/round6/`](ux_screenshots/round6/) are captured as evidence
> for the human reader; the reviewer's own analysis is grounded in the probes'
> **visible-text dumps** + the source (`file:line`) + the live app/HTTP logs.
> Where a screenshot's exact pixel state could not be textually confirmed, it is
> stated.

### App-run + probe commands used

```bash
# 1. Real backend, seeded with the Wave-3 honest curated TS scripts:
just api-dev-up                       # → http://127.0.0.1:35799, healthy
source .just-tmp/api-env.sh           # exports MARKETPLACE_API_PORT
cd backend && bash scripts/add-sample-data.sh   # idempotent; 3 curated TS scripts

# 2. Rebuild the release binary FIRST (Round-5 lesson: stale binary misleads).
#    Release ignores UXR5-7's debug-only env override, so to point at the local
#    backend the build pins the endpoint (as Round-5 did):
cd apps/autorun_flutter && flutter build linux --release \
  --dart-define=PUBLIC_API_ENDPOINT=http://127.0.0.1:$MARKETPLACE_API_PORT \
  --dart-define=MARKETPLACE_WEB_URL=http://127.0.0.1:$MARKETPLACE_API_PORT

# 3. Live GTK launch under Xvfb + mock keyring (foreground, timeout-bounded):
scripts/run-with-mock-keyring.sh --display :99 \
  ./apps/autorun_flutter/build/linux/x64/release/bundle/icp_autorun

# 4. Integration probes (real widgets, real backend, text dumps + screenshots):
cd apps/autorun_flutter && source ../../.just-tmp/api-env.sh && \
  flutter test --no-pub /tmp/opencode/probe_round6/<probe>.dart
```

### Screens + dumps captured (in [`ux_screenshots/round6/`](ux_screenshots/round6/))

| File | Surface | How captured |
|---|---|---|
| `dumps/A_details_hello-ic-starter.txt` + `.png` | Details dialog — FREE "Hello IC Starter" (TS badge over real TS) | Probe A (render tree) |
| `dumps/A_details_icp-balance-reader.txt` + `.png` | Details dialog — PAID, teaser + "Buy for $1.99" | Probe A |
| `dumps/A_details_interactive-counter.txt` + `.png` | Details dialog — PAID, teaser + "Buy for $4.99" | Probe A |
| `dumps/D_wizard.txt` + `D_wizard.png` | First-run wizard form ("Marketplace username (optional)") | Probe D |
| `dumps/C_account_local.txt` + `C_account_local.png` | Account screen, local-only, Passkeys hint | Probe C |
| `dumps/E_timeout.txt` | Browse timeout wall-clock (TCP tarpit) | Probe E |
| `dumps/F_icpay.txt` | ICPay 503 → PaymentsNotConfiguredException | Probe F |
| `dumps/G_port.txt` | `MARKETPLACE_API_PORT` honored at runtime (debug) | Probe G |
| `dumps/H_details_desktop.txt` + `H_details_desktop.png` | Details dialog @1440×900 (overflow check) | Probe H |
| `live_gtk_t5.png` | Live GTK release binary under Xvfb + mock keyring | `import -window root` |

---

## 0. Verification table — all seven Wave-3 fixes VERIFIED live

Driven live + grounded in source on 2026-07-09. **Every Wave-3 fix behaves as
specified against the real backend.** Evidence is the actual visible text the
probes dumped (not a claim).

| Wave-3 WU | Status | Live evidence (this round) |
|---|---|---|
| **UXR5-3** Shorter browse timeout (45 s → ~8 s) | ✅ **VERIFIED** | Probe `E_timeout.txt`: a real TCP tarpit (accept, never reply) hangs `getTrendingScripts`; it errored after **exactly 8.01 s** (`TimeoutException after 0:00:08`), not 45 s. Wired via `AppDurations.browseTimeout = Duration(seconds: 8)` (`theme/app_design_system.dart:745`); downloads keep `downloadTimeout = 45 s` (`:750`). The single `_timeout` field is gone (no orphan). |
| **UXR5-2** Honest language badge (detect from bundle) | ✅ **VERIFIED (TS live; Lua via gating test)** | Probe `A_details_*.txt`: all three seeded scripts render the **`Code Preview` → `TypeScript`** badge above **real TypeScript** source (`"use strict"; (() => { function init() … globalThis.init = init;`) — compare Round-5's "TypeScript" badge over Lua (`function init(arg) … end`). The badge now reads the backend-**detected** `language` (`widgets/script_details_dialog.dart:231-261`, `_buildLanguageBadge`/`_languageBadgeLabel`), and the backend detects from content (`backend/src/script_language.rs:59 ScriptLanguage::detect`; Lua wins ties → never badged TS). No seeded script is Lua, so the **"Legacy Lua"** amber path is covered by the gating test `test/features/marketplace/script_details_language_badge_test.dart:103` (asserts Lua renders "Legacy Lua", **not** "TypeScript") + 8 detector unit tests — not separately live-driven (honest gap). |
| **UXR5-1** Honest curated marketplace seed | ✅ **VERIFIED** | `GET /api/v1/scripts/trending` returns exactly **3 honest, curated scripts** with real titles/authors/descriptions: **"Hello IC Starter"** (FREE, Alice Developer — "The canonical first ICP script"), **"ICP Balance Reader"** ($1.99, Bob Coder — "Query the ICP ledger canister and display a formatted balance"), **"Interactive Counter"** ($4.99, GameDev Pro — "A stateful counter with increment and reset"). **NO** "Updated Title", "List Test Script 1/2", or "My Test Script for Publishing" (the Round-5 slop). Probe `A_details_*.txt` renders them verbatim. Bundles are real TS (mirrors `examples/01_hello_world.js`, `02_canister_query.js`, `05_typescript_counter.js`). |
| **UXR5-5** Wizard: connected "Marketplace username (optional)" label | ✅ **VERIFIED** | Probe `D_wizard.txt` line 7: **`Marketplace username (optional)`** — the single, connected label. The free-floating bare **`Marketplace`** chip is **gone** (Round-5 had it between "Username (optional)" and the field). The description line is preserved ("Create a marketplace account to share scripts and interact with the community"). Hard assertion in the probe: `find.text('Marketplace')` → `findsNothing`. Source: `unified_setup_wizard.dart:399`. |
| **UXR5-6** Passkey hint for local-only users | ✅ **VERIFIED** | Probe `C_account_local.txt`: the local-only body now renders a disabled **`Passkeys`** title with **`Available after you register a marketplace account. On Linux, passkeys need a browser (macOS, Windows, or Android).`** — honest prerequisite + the existing browser-only note. Hard assertions: `find.text('Passkeys')` → `findsOneWidget`; `find.textContaining('Available after you register')` → `findsWidgets`. Source: `account_profile_screen.dart:1293-1343` `_buildLocalOnlyPasskeyHint`. |
| **UXR5-4** Honest non-transient ICPay-degraded copy | ✅ **VERIFIED** | Probe `F_icpay.txt`: the live backend returns **HTTP 503** for `/payments/icpay/config`, and the real `IcpayService.loadConfig` throws **`PaymentsNotConfiguredException: ICPay publishable key not set on server`** — the exact trigger. The copy it surfaces is now **`"Payments aren't available on this server yet."`** (`screens/scripts_screen.dart:629`); the misleading **"Try again later"** is **gone** (`rg "Try again later" scripts_screen.dart` → no match). |
| **UXR5-7** `MARKETPLACE_API_PORT` honored at runtime (debug) | ✅ **VERIFIED** | Probe `G_port.txt`: in debug (`kDebugMode = true`), with **no** `--dart-define`, `AppConfig.apiEndpoint` returns **`http://127.0.0.1:35799`** derived purely from the exported `MARKETPLACE_API_PORT=35799` env var; `isLocalDevelopment = true`. Source: `config/app_config.dart:23-30` (debug branch guarded by `kDebugMode`; release keeps the build-time default — correct). |

> **Net: 7 / 7 Wave-3 fixes VERIFIED live.** This is a clean, high-quality
> finish. The three Round-5 P1s (slop seed, Lua-over-TypeScript, 45 s spinner)
> are all genuinely resolved, and the four P2s landed cleanly.

---

## 1. New findings (residual friction)

Severity-ranked, with concrete proposals. Each was observed **live** this round.

### NF-1 — Details dialog: right-panel Statistics clip at small window heights  [P2]

- **What:** At the **default** desktop window (1280×720, `my_application.cc:56`)
  the dialog is fine (probe `H_details_desktop.txt` → **0 overflows** at
  1440×900). But the app **enforces no minimum window size**, so a user who
  shrinks the window (or runs at low resolution) hits a `RenderFlex overflowed
  by N pixels on the bottom` in the wide layout's right-hand Statistics column
  (`widgets/script_details_dialog.dart:653` — the Buy-CTA + Statistics `Column`).
  At the 800×600 test surface this clipped by **92 px**; the left description
  column (`:495`) clipped by 6–22 px. The clipped stats (Downloads / Rating /
  Version / Updated / Compatible Canisters) become partially invisible — the
  yellow/black stripe Flutter draws in debug.
- **Grounding:** probe `A_details_interactive-counter` run output logged
  `RenderFlex overflowed by 92 pixels` → `Column script_details_dialog.dart:653`;
  probe `H` at 1440×900 → `overflow_count=0`. The wide layout's right panel is a
  non-flex `Column` with no scroll view.
- **Proposal:** wrap the right-panel `Column` (`:653`) in an
  `SingleChildScrollView` (or give the stats region an `Expanded` + `ListView`),
  so a short window scrolls instead of clipping. Optionally set a sensible
  `gtk_window_set_default_size`-aligned minimum on the dialog.
- **Confidence:** correct **8/10**, safe **9/10**. (Additive, layout-only.)
- **Why P2 not P1:** only triggers below the default window size; cosmetic clip,
  no crash/data loss; the dialog is otherwise excellent.

### NF-2 — Mock Secret Service is `plain`-only; DH-preferring libsecret crashes it (devex/honesty)  [P2, devex]

- **What:** `scripts/mock_secret_service.py:90-93` only supports the `plain`
  session algorithm. This box's `libsecret` negotiates the encrypted
  **`dh-ietf1024-sha256-aes128-cbc-pkcs7`** key exchange; the mock raises
  `NOT_SUPPORTED` (with the shipped mock) / crashes with `EOFError` on
  `unmarshall` (even when `OpenSession` is patched to accept the DH string,
  because the secret payload is then AES-encrypted with a key the mock never
  agreed). Result: `SecureStorageReadiness().check()` does **not** return
  `StorageReady` here → the live app shows the **WU-S2 blocking
  storage-unavailable panel**, and the first-run wizard form **cannot be driven
  live on this box** (no `gnome-keyring-daemon` installed either). `AGENTS.md`
  claims the mock is "Verified end-to-end" — that verification is
  **environment-dependent** (it holds where libsecret negotiates `plain`).
- **Grounding:** probe `S` (storage readiness under the mock) → `EOFError` at
  `secure_storage_readiness.dart:514 _probeOnce`; live app log shows the
  `algorithm 'dh-ietf1024-sha256-aes128-cbc-pkcs7' not supported` DBusError.
- **Impact on THIS review:** none — all 7 Wave-3 items are verified via probes
  (the wizard-form text comes from probe D, which injects `StorageReady` to
  render the real wizard widget). It DOES block a live wizard-form screenshot.
- **Proposal:** either (a) implement the DH key exchange (IANA group 2) +
  AES-128-CBC-PKCS7 decrypt in the mock so encrypted libsecret sessions
  round-trip, or (b) at minimum make the mock degrade **without crashing**
  (catch the unmarshall failure, return an empty/plain secret so
  `SecureStorageReadiness` cleanly reports `unavailable` instead of throwing),
  and add a note in `AGENTS.md` that libsecret-version sensitivity exists. Option
  (b) is the honest, low-effort floor.
- **Confidence:** correct **9/10** (reproduced deterministically), safe **9/10**
  (dev-tooling only; no product change).

> No other new friction found. The premium-quality lens: the details dialog
> (lazy tabs, real `/preview`, paid gate + Buy CTA, Esc/←/→ shortcuts, copy
> preview), the wizard (single screen, inline validation, honest optional
> field), and the account screen (honest status, Import/Export always visible,
> pedagogical tooltips, passkey hint) are all **excellent**. Click-counts are
> low, copy is honest, no AI slop/stubs remain in the shipped seed.

---

## 2. What was NOT driven live (honest gaps)

- **The live first-run wizard FORM screenshot** is blocked by NF-2: this box has
  no `gnome-keyring-daemon` and its libsecret prefers the DH/AES session the mock
  can't complete, so storage doesn't round-trip and the live app shows the WU-S2
  blocking panel (correct fail-loud behavior). The wizard-form **text** is fully
  verified by probe D (real `UnifiedSetupWizard` widget with `StorageReady`
  injected — the same widget the live app renders). `live_gtk_t5.png` captures
  the live binary running; I cannot visually confirm which panel it shows
  (image-viewing limitation), but probe S confirms storage is unavailable here,
  so by WU-S2 logic it is the blocking panel.
- **The "Legacy Lua" badge** (the other half of UXR5-2's acceptance) is not
  live-driven: no seeded script is Lua (by design — the runtime is TS-only). It
  is pinned by the gating test `script_details_language_badge_test.dart:103` +
  8 backend detector unit tests. I did **not** inject a temporary Lua script via
  the API to verify it live, because doing so would re-introduce test slop into
  the curated seed (the exact thing UXR5-1 removed) — a net-negative trade.
- **The full ScriptsScreen browse grid (card layout/density)** was not pumped:
  the deep controller wiring + a transitive WebSocket dependency in the harness
  make a full pump flaky (same harness artifact Round-5 hit). Browse **content**
  is instead evidenced by the `trending` API dump (3 honest scripts) + the three
  details probes. Not a confirmed user-facing bug.
- **Genuine passkey round-trip / ICPay checkout / Vault tap:** out of scope
  headlessly — passkeys need a real browser (AGENTS.md); ICPay returns 503
  (unconfigured) so there is no live checkout to drive; `xdotool` is unavailable
  so menu/sheet navigation can't be pixel-driven. The ICPay **trigger** (503 →
  typed exception → honest copy) is verified live (probe F).

---

## 3. Top friction — per audited surface (this round)

- **First-run wizard:** UXR5-5 resolved — `Marketplace username (optional)` is a
  single, unambiguous label. Otherwise genuinely low-friction, single screen.
- **Marketplace + details:** UXR5-1/2/3/4 all resolved — honest curated seed,
  TS badge over real TS, ~8 s browse timeout, honest ICPay copy. The only
  residual is NF-1 (right-panel clip at small windows). The dialog itself (lazy
  tabs, real preview, paid gate + Buy CTA, Esc/←/→) is excellent.
- **Account (local-only):** UXR5-6 resolved — honest Passkeys hint with the
  Linux browser-only note. Import/Export always visible; honest status badge.
- **Dev/onboarding:** UXR5-7 resolved (debug env-var honoring). NF-2 is the
  remaining devex gap (mock vs DH libsecret).

---

## Confidence: 9 / 10

- **High confidence** on all 7 Wave-3 VERIFIED items: each is backed by an
  authoritative probe text dump (or a wall-clock measurement / live HTTP
  response) + `file:line` + the gating test. The three Round-5 P1s are
  unambiguously fixed live.
- **Held-back point** because: (a) the reviewer cannot view images (analysis
  rests on text dumps + code, per the honesty note); (b) the live wizard-form
  screenshot is blocked by NF-2 (env/mock incompatibility), so the wizard is
  verified via probe, not via the live GTK window; (c) the Lua-badge path and
  the full browse grid are covered by gating tests / API dumps rather than a
  live card dump; (d) NF-1's real-world frequency depends on how often users
  shrink the window below the 1280×720 default (estimated low).

No application source was modified. Probe code lives in
`/tmp/opencode/probe_round6/` (outside the repo). The only repo additions are
this document + `docs/specs/ux_screenshots/round6/` (screenshots + text dumps).
