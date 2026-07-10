# Quality Sweep — Functional, Visual & Tech-Debt Fixes (Wave-4)

- **Status:** ✅ COMPLETE (all 11 WUs landed + verified) — extends (does not redo) the completed
  [`2026-07-08-quality-initiative.md`](2026-07-08-quality-initiative.md)
  (Wave-1/2/3 COMPLETE) and the web-gap WUs (WU-1/2/3 COMPLETE).
- **Date:** 2026-07-10
- **Scope:** Linux desktop (`flutter run -d linux`) + backend (Rust/Poem) +
  Flutter Web. Full app: marketplace, scripts, dapps, profile/account,
  passkey/vault, onboarding.
- **Method:** empirically grounded (every claim cited to `file:line` or a live
  observation), PoC-first, one commit per unit. Orchestrated via subagent
  swarms (planner → implementers → verifiers).
- **Predecessors (DONE, not reopened):**
  - `2026-07-08-quality-initiative.md` — TD-1..8, TQ-1/2, UX-1, AL-1, UXR5-1..7
  - `2026-07-09-web-remaining-gaps.md` — WU-1/2/3 (Web JSON store, secp256k1,
    doc hygiene)
  - `2026-07-08-ux-review-round6.md` — NF-1/NF-2 fixed; 7/7 Wave-3 verified.

---

## §0. Baseline measured on 2026-07-10

| Check | Verdict | Evidence |
|-------|---------|----------|
| `flutter analyze` | ✅ CLEAN | "No issues found!" (3.5s) |
| Flutter tests (via `just`) | ✅ GREEN w/ LD_LIBRARY_PATH | `LD_LIBRARY_PATH=target/release flutter test` → green; the 34 failures seen running `flutter test` *bare* are the missing lib path, NOT product bugs. |
| Native lib `libicp_core.so` | ✅ BUILT | `target/release/libicp_core.so` present |
| Largest file | `account_profile_screen.dart` 1977 (under 2k rule) | `wc -l` |

> The app is in a healthy, well-tested state. This plan hunts for *residual*
> functional/visual issues and tech debt via a fresh empirical scan + a live UX
> review, not a re-do of prior waves.

---

## §1. Work Units (populated by the planner + UX-review findings)

> Format mirrors the predecessor plan. **QS-** prefix = Quality Sweep. Each WU:
> PoC-first, one commit, `flutter analyze` clean + cited tests green.

### QS-1 — Fix Reviews tab cast crash (UXR7-1) [P1]

**Symptom:** Opening *any* script's Reviews tab throws
`type '_Map<String, dynamic>' is not a subtype of type 'List<dynamic>'`.
Reproduced live for free + paid scripts.

**Root cause:** `marketplace_open_api_service.dart:356` does
`final data = responseData['data'] as List;` but the backend returns `data` as a
Map `{"reviews":[…],"hasMore":bool,"total":int}` (confirmed via curl).

**Fix:** Read `responseData['data']` as a Map, then take `['reviews']` as the
list. Pass through `hasMore`/`total` to the caller. Fix the masking widget test
(`script_details_reviews_test.dart:62-75`) to mock the *real* backend shape
(bare array → `{reviews:[…],hasMore,total}`), so it would have caught this.

### QS-2 — Unify Candid parse path with the robust parser (F-1, F-2, TD-9) [P1]

**Symptoms:**
- F-1: ICRC methods (`symbol`, `decimals`, `total_supply`) classified as
  *update* by name-prefix heuristic → calls go out wrong on the live path.
- F-2: malformed Candid → silent `return []` → empty dropdown, no error.
- TD-9: a "basic implementation / want robust parser" comment ships in prod.

**Root cause:** `_parseCandidMethods` (`candid_service.dart:214-217`) uses a
regex scratch-parser + `_inferMethodMode` (`:250-266`) classifies by name
prefix, discarding the Candid `query`/`update` annotation. A robust 1103-line
pure-Dart parser already exists (`candid_interface_parser.dart`).

**Fix (highest-leverage single change):** Route `_parseCandidMethods` through
`candid_interface_parser.dart`, which preserves the query/update annotation.
Delete the regex scratch-parser + name-prefix heuristic + the "basic" comment.
Replace F-2's `catch (e) { return []; }` with typed match-style error handling
(consistent with TD-3's fetch-half fix).

### QS-3 — Stop bookmarks corrupt-load data loss (F-3) [P2, data-loss]

**Root cause:** `bookmarks_service.dart:113-116` swallows corrupt-load errors →
resets cache to `[]` → next save overwrites the file → **permanent bookmark
loss**.

**Fix:** On corrupt-load, surface the typed error (do NOT reset cache). Only an
explicit, confirmed-empty/missing file yields `[]`. Add a negative test that
seeds a corrupt file and asserts no overwrite + loud error.

### QS-4 — Wire up download-history item tap (UXR7-2) [P2]

**Symptom:** Tapping a downloaded script looks it up, then *only pops* — never
opens/runs/highlights it (stale TODO admits intent). Primary interaction on a
populated library is a no-op.

**Fix:** On tap, open the script detail/run sheet (the existing flow used
elsewhere). Remove the stale TODO.

### QS-5 — Settings single-source + dynamic version (UXR7-3, UXR7-5) [P2]

- UXR7-3: Settings "Marketplace Website" link hardcodes
  `https://icp-mp.kalaj.org` (`settings_screen.dart:47`); replace with
  `AppConfig.marketplaceWebUrl` (honors `MARKETPLACE_WEB_URL` dart-define).
- UXR7-5: Settings hardcodes version "Version 1.0.0 (1)"; replace with
  `package_info_plus`.

### QS-6 — Download-history naming + navigation (UXR7-4, UXR7-6) [P2]

- UXR7-4: unify the 3-way naming (menu/AppBar/empty-state) to one label.
- UXR7-6: "Browse Marketplace" empty-state CTA must navigate to the browse tab,
  not pop + tell the user to switch manually.

### QS-7 — Remove orphaned `MyLibraryScreen` dead code (UXR7-7) [P2]

`MyLibraryScreen` is referenced only in its own test; wired nowhere into
navigation; duplicates DownloadHistory. Delete the screen + its test.

### QS-8 — Add candid parse/mode gating tests (TQ-4) [P2] — ✅ folded into QS-2

Folded into QS-2 (11 tests in `candid_parse_test.dart`: ICRC query methods →
mode 0, update → mode 1, composite_query → mode 2, malformed → typed error).

### QS-9 — Document remaining defensible `catch (_)` + bounds (TD-10, TD-11, TD-12) [P3]

- TD-10: 5 `catch (_)` in `lib/rust/web/` (R-3) — document or tighten.
- TD-11: `download_history` generic-catch-for-not-found — tighten to typed.
- TD-12: unbounded `/etc/os-release` read — bound it.

---

## §2. Execution order + parallelism

Serialized (shared working tree/git/index). Suggested order:

1. **QS-1** (reviews cast) — highest user impact; touches
   `marketplace_open_api_service.dart` + its test.
2. **QS-2** (candid unify) — highest leverage (resolves 3 findings); touches
   `candid_service.dart` + `candid_interface_parser.dart`.
3. **QS-3** (bookmarks data-loss) — isolated to `bookmarks_service.dart`.
4. **QS-4** (download-history tap) — `download_history_screen.dart`.
5. **QS-5** (settings) — `settings_screen.dart`.
6. **QS-6** (naming + nav) — `download_history_screen.dart` + nav.
7. **QS-7** (delete orphan) — `my_library_screen.dart` + its test.
8. **QS-8** (candid tests) — `test/features/...`.
9. **QS-9** (P3 doc/tighten) — `lib/rust/web/` + misc.

QS-1 → QS-2 may be parallelized *only* if no file overlap (they don't overlap,
but serialization is safer for the shared git index per AGENTS.md).

---

## §3. Success criteria (Definition of Done)

Same bar as predecessor §4/DoD:
- User-visible change reachable from the running app.
- `flutter analyze` clean; cited `just test-feature <name>` green; `cargo nextest`+`clippy` green.
- No silent errors; single-source constants; typed errors not heuristics.
- Confidence ≥ 8/10.
- One commit per unit.

---

## §4. Change log

All WUs landed, verified, and committed. Final gate: `cargo nextest` 281/281,
`flutter analyze` clean, `flutter test` 1255 passed / 11 skipped / 0 failed
(non-integration). UX re-verification: 4/5 fixes verified live; UXR7-1 required
a follow-up (QS-1b) caught by live probing — now resolved end-to-end.

| WU | Commit | Summary |
|----|--------|---------|
| QS-1 | `eb6839be` | Reviews tab: read backend `data` as Map, extract `reviews` list. Typed `MalformedReviewsResponseException`. Fixed masking test to real shape. +3 contract tests. |
| QS-2 | `3c7a5b83` | Candid: deleted regex scratch-parser + `_inferMethodMode` name-prefix heuristic; routed through robust `parseCandidInterface` (preserves query/update annotation). Typed `CandidParseException`. 11 new tests. (Also covers QS-8/TQ-4.) |
| QS-3 | `c752ccf2` | Bookmarks: corrupt-load throws typed `BookmarksLoadException` (cache never poisoned); `add()`/`remove()` load-first (corrupt file never overwritten). 10 new tests prove file-untouched + save-blocked. |
| QS-4 | `5f00b0d1` | Download-history tap: calls shared `runLocalScript()` helper (DRY, reused from scripts_screen). Opens execution sheet as overlay (no dead pop). DI seam for testability. 2 new tests. |
| QS-5 | `4cddb397` | Settings: hardcoded URL → `AppConfig.marketplaceWebUrl`; hardcoded version → `PackageInfo.fromPlatform()`. |
| QS-6 | `3e85b253` | Download-history: unified all naming to "Download History"; "Browse Marketplace" CTA pops + fires `onBrowseMarketplace` callback. 2 new nav tests. |
| QS-7 | `4092810b` | Deleted orphaned `MyLibraryScreen` (480 lines) + test (266 lines). `FavoritesService` kept (used live). |
| QS-9 | `4a2ccd28` | TD-11: download-history `_loadHistory` generic catch → typed `on FormatException`. TD-12: bounded os-release read to 8 KiB. TD-10: documented 5 defensible `catch(_)` in `lib/rust/web/`. |
| cleanup | `a31387d1` | Removed unused `ModernErrorDisplay`/`ShakeCurve` (debug crash, 163 lines dead code). |
| QS-10 | `cf575917` | Download-history `_saveHistory` silent swallow → loud `debugPrint` + rethrow (callers already surface via SnackBar). 3 new failure-path tests. |
| QS-1b | `8e6a948d` | **Regression caught by live UX verification:** QS-1 fixed the Map/List cast but `ScriptReview.fromJson` threw `Null is not String` — backend `Review` struct lacked `#[serde(rename_all = "camelCase")]` (every other struct had it). Added the attribute; rewrote masking test to real payload; 2 Rust serde lock-in tests + live curl + live Flutter probe all confirm camelCase. |
