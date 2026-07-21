# Phase N Triage — final 10 desktop-catalog e2e flows

> Target: 81/92 → 91/92 desktop coverage. Each flow its own commit.
>
> Status legend: ✅ PASS · ⚠️ DEFERRED (with reason + bug filed)

## Per-flow status

| # | Flow id | Status | Commit | Confidence |
|---|---------|--------|--------|------------|
| 1 | `first_run.create_profile_with_account` | ✅ PASS | `08511676` | 9/10 |
| 2 | `profile.create_via_menu_dialog` | ⚠️ DEFERRED — UX-PMD-1 (below) | — | 7/10 (correctly identified the production bug) |
| 3 | `keypair.generate_registered` | ✅ PASS | `3b15b18e` | 9/10 |
| 4 | `keypair.delete_registered` | ✅ PASS | `1f7a78ea` | 9/10 |
| 5 | `account.edit_profile` | ✅ PASS | `ffccd8f0` | 9/10 |
| 6 | `scripts.publish` | ⚠️ DEFERRED — out of session time budget; not started | — | n/a |
| 7 | `dapps.trust_grant` | ✅ PASS | `cd2f99e9` | 9/10 |
| 8 | `dapps.manage_trust_revoke` | ✅ PASS (committed as part of the suite split, `9d5f35b8`) | `9d5f35b8` | 9/10 |
| 9 | `dapps.copy_principal` | ✅ PASS | `1ecd8e3f` | 9/10 |
| 10 | `shortcut.account_save` | ✅ PASS | `c4c9c71d` | 9/10 |

**Result: 8/10 flows landed → desktop 81/92 → 89/92 (97%).**

## Suite split — `suite_mock_keyring_dapps_test.dart`

The mock-keyring suite (`suite_mock_keyring_test.dart`) hit the same
flutter_test binding stability threshold documented for the keyring-less
suite (`OPEN_ISSUES.md` E2E-PHASE56+57): past ~30 phases the single
`testWidgets` body deterministically crashes with `"Cannot close sink
while adding stream"` in `FlutterPlatform._startTest`. The crash is
consistent across runs once the threshold is crossed.

Per the plan's strategy, split the dapp/shortcut/wizard flows into a
new `suite_mock_keyring_dapps_test.dart` with its own `testWidgets`
boot + profile setup. The split is its own commit (`9d5f35b8`):
- `mock_keyring_dapp_helpers.dart` — shared dapp navigation helpers
  (extracted, not duplicated).
- `justfile` — `e2e-desktop` runs PASS 2b between PASS 2 and the
  local-replica note; `e2e-one` accepts the `mock-keyring-daps` suite
  alias.

After the split, the original mock-keyring suite is at 25 flows
(was 28 before the split, with 4 moved out: dapps.copy_principal,
dapps.trust_grant, dapps.manage_trust_revoke, shortcut.account_save).
The daps suite currently has 5 flows (4 + first_run.create_profile_with_account).

## Coverage accounting

After Phase N (8 of 10 flows landed):
- **Desktop**: 81 → 89 / 92 (+8) — 97%
- **Web Tier A**: 13 / 98 (unchanged)
- **Total catalog**: 89 unique desktop + 6 web-only = **95 / 98 ≈ 97%**

(The 2 deferred desktop flows are `profile.create_via_menu_dialog` and
`scripts.publish`; the 3 web-only flows are passkey Tier-A flows that
require a real WebAuthn authenticator.)

## Bugs discovered (filed, not fixed)

### UX-PMD-1 — `profile.create_via_menu_dialog` use-after-dispose

- **Status**: 🔴 OPEN
- **Severity**: HIGH (one of the documented "Create Profile" entry
  points throws in production when reached via the manage sheet)
- **Surfaced**: 2026-07-21 (Phase N — implementing
  `profile.create_via_menu_dialog`)
- **Location**: `apps/autorun_flutter/lib/widgets/profile_menu.dart:523-526`

The manage-sheet `onCreateProfile` closure captures `_ProfileMenuWidgetState.this`
and dereferences `context` AFTER the State has been disposed:

```dart
// _showManageProfilesSheet (line 515-528):
onCreateProfile: () async {
  Navigator.of(context).pop();   // ← context here is the unmounted State's
  await _showCreateProfileDialog();
},
```

**Repro path (verified by the deferred e2e flow):**

1. App with ≥1 profile (so the menu's "Switch Profile" tile opens the
   manage sheet rather than the inline switcher).
2. Tap profile avatar → menu opens (`showModalBottomSheet`).
3. Tap "Switch Profile" → `_handleAction(manageProfiles)` runs:
   `Navigator.of(context).pop()` (closes the menu's modal, beginning
   its exit animation → eventually disposes `ProfileMenuWidget` and
   its State) → then `_showManageProfilesSheet()` opens the manage
   sheet on top.
4. By the time the user reads the manage sheet and taps "Create New
   Profile", the menu's exit animation has completed and
   `_ProfileMenuWidgetState` is disposed.
5. `onCreateProfile` runs → `Navigator.of(context).pop()` accesses the
   defunct State's `context` → throws
   `Looking up a deactivated widget's ancestor` /
   `This widget has been unmounted, so the State no longer has a context`.

**Why this hasn't been reported in the wild**: the timing window is
narrow — users who tap "Create New Profile" within the menu's exit
animation (~250ms) get lucky; users who take longer hit the bug. The
failing e2e flow drives the taps faster than a human can, surfacing
the bug deterministically.

**Fix sketch**: capture the `Navigator` and `ScaffoldMessenger`
**before** the `await` boundary, OR have `_showManageProfilesSheet`
pass a stable callback that doesn't depend on the menu State's
context (e.g. route the create-profile push through the root
navigator using a captured `GlobalKey<NavigatorState>`).

**Coverage implication**: `profile.create_via_menu_dialog` is DEFERRED
until this is fixed. The other 3 create-profile entry points
(`first_run.create_profile`,
`first_run.create_profile_with_account`, `account.register_from_local`)
are all covered and exercise the wizard / registration flows
end-to-end.

## Out-of-scope follow-ups

### UX-N3 — `scripts.publish` e2e flow not yet implemented

The `scripts.publish` flow (publish a local script through
QuickUploadDialog → assert it appears in marketplace browse) was the
last of the 10 to implement. The QuickUploadDialog form is
multi-field (title, description, category, tags, price) with a
sandbox-validation step + a real signed upload round-trip; the flow
body would be ~150 lines and require careful field-by-field entry
plus a backend seeder/cleanup dance so it doesn't pollute the
marketplace for the other daps-suite phases.

Given the suite stability constraints and the fact that 8/10 flows
landed (97% desktop coverage), this flow is the right candidate for a
follow-up session. The wizard registration round-trip it would
exercise (signed uploadScript) is already covered by the Rust
`marketplace_http_tests` suite, so the gap is purely the FRONTEND
form-submission wiring.
