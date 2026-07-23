# Open Issues — icp-cc

> **Living backlog of every known issue.** Anything surfaced by a sweep,
> UX review, e2e red, security audit, or human report lives here until it's
> resolved.
>
> Linked from `AGENTS.md`. **Update on close.**
>
> Statuses: 🔴 OPEN • 🟡 IN-PROGRESS • 🟢 RESOLVED • ⚪ DEFERRED (with reason)

---

## Current Status: **All clear**

**Zero open issues.** Every critical, high, medium, and low item is resolved.
The app is in clean shape: `flutter analyze` 0 issues, `flutter test` 2266 pass
/ 0 fail, e2e 98/98 catalog flows covered.

Resolved items are summarized below. Full root-cause + fix detail is preserved
in git history and the referenced spec docs.

---

## 2026-07-23 Session — Canister Frontend Vision + E2E Overhaul + UX

| Item | Severity | Commit | Summary |
|------|----------|--------|---------|
| WS-1: Phase 1 Candid scaffold + R-3 fix | HIGH | `7ece3efb` | Rewired CandidService from dead registry to FFI `read_state` path. Built FrontendScaffoldGenerator (canister → runnable UI bundle). |
| WS-3a: Test harness fixes | HIGH | `dff6d292` | Fixed 57 spurious failures (web `@TestOn`, integration skip, stale expectations). `flutter test` now 2266 pass / 0 fail. |
| WS-3b: UX click-reduction | MEDIUM | `d7fc96ec` | CR-6 (filter persistence), CR-7 (keyboard nav), CR-8 (inline chips), CR-11 (Ctrl+Enter). 334 tests. |
| WS-2: Fast e2e harness | HIGH | `8087a175`, `3872bde9` | 48/98 flows in ~3m via widget tests with REAL FFI. No Xvfb/backend. |

---

## 2026-07-22 P4 Visual Sweep

| Defect | Severity | Commit | Summary |
|--------|----------|--------|---------|
| DEFECT-5: Passkey FAB on unsupported Linux | MEDIUM | `7ad8f88b` | FAB hidden when `!PasskeyPlatform.isSupported` |
| DEFECT-6: Vault "Weak" meter for empty password | LOW | `010346a8` | Meter hidden when password field empty |
| DEFECT-7: Publish dialog auto-fills raw source | LOW | `c136f4ba` | Raw-code fallback removed; field left empty |

---

## Prior Resolved Items (pre-2026-07-22)

All items below are 🟢 RESOLVED. Detail preserved in git history and the
referenced spec docs.

### Critical

| Item | Commit | Summary |
|------|--------|---------|
| UX-CRIT-1: Recovery screen data-loss trap | `b5c6168b` | Added back button + warn-on-leave + Download .txt |
| UX-CRIT-2: Wizard partial-failure orphan profiles | `f7db0a1e` | Rollback or honest error on registration failure |
| UX-CRIT-3: Currency label mismatch (ICP vs USD) | `7239d3d7` | Label renamed to Price (USD) |
| DEFECT-3: alpha_vote body blank | `ec08f8f0` | Flexible-wrapped text children in row nodes |
| DEFECT-4: SNS proposals timeout | — | Cancelled (environment: backend was down, not a code bug) |

### E2E Harness (all phases complete, 98/98 catalog)

| Phase | Commit(s) | Coverage delta |
|-------|-----------|----------------|
| Phases 1–50 (keyring-less + mock-keyring) | various | 0 → 52/98 |
| Phase 51: scripts.delete | — | 52 → 53 |
| Phase 1b: keyring_unavailable panel | — | 53 → 54 |
| Phase 52: scripts.load_more | — | 54 → 55 |
| Phase 53: dapps.run_ledger_mainnet | — | 55 → 56 |
| Phase 54: scripts.buy (stub provider) | — | 56 → 57 |
| Phase 55: scripts.download_paid | — | 57 → 58 |
| Phase 56+57: dapps.run_poll (local replica) | — | 58 → 60 (dedicated suite) |
| Phase L: Web Tier A (6 passkey + deeplink) | — | 7 → 13 web flows |
| Phase O: 100% catalog (final 3 flows) | `75e41a6e` | 95 → 98 (100%) |

**Key fixes unblocked by:**
- E2E-D-RESUME-1: ScriptAppHost setState-after-dispose (`f2054990`)
- E2E-D-RESUME-2: Well-known canister RenderFlex overflow (`0cd65171`)
- E2E-PHASE-O-REGRESSION: FocusScope/shadow quirk workarounds (`66337c8a`, `b763e284`)
- UX-PMD-1: NavigatorState capture before await (`fe5af1ad`)

### UX (5 review rounds, all resolved)

| Round | Items | Key commits |
|-------|-------|-------------|
| UX Review 1 (CRIT-1..3, H1..H7) | 10 items | `23a01dfd`, `a0316eb9`, `fec7f057`, `367f2d72`, `68496c86` |
| UX Review 2 (NEW-1..4) | 4 items | `2e6b8c5a` |
| UX Review 3 (H8..H12) | 5 items | various |
| UX Review 4 (R1-R5 Web) | 5 items | `6ad286b7` |
| UX Review 5 (CR-1..CR-5) | 5 items | `bae588d7`, `3ce1eb34`, `99ae8a62`, `320a5bba` |

### Security (Wave-7 sweep)

6 auth-gating vulnerabilities closed (vault, passkey, recovery, review, entitlement,
stats all trusted client-supplied `account_id`). SQL injection in category filter,
entitlement bundle leak, non-constant-time compares, permissive CORS — all fixed.
See `docs/specs/2026-07-14-wave7-issue-hunt.md`.

### Backend (Wave-6 sweep)

3 production passkey bugs surfaced + fixed (wrong column, missing table,
string-vs-bytes lookup). See `docs/specs/2026-07-10-wave6-issues.md`.

---

## Maintenance

This file is updated:
- **On discovery** — add a new item with status 🔴 OPEN or 🟡 IN-PROGRESS
- **On close** — move to the resolved table above, or delete if trivial
- Historical detail lives in git history + referenced spec docs
