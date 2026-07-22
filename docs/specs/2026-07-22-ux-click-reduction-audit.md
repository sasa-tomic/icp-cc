# UX Click-Reduction Audit — All App Screens (2026-07-22)

> **Read-only UX audit.** No application code was changed. This document is a
> planning deliverable: every recommendation is grounded in the source of a
> specific screen, with a measured before/after click count.
>
> **Scope:** every user-facing screen in `apps/autorun_flutter/lib/screens/`
> (20 files) + the navigation shell (`main.dart`) + the shared widgets that
> drive the primary flows (`profile_menu.dart`, `quick_upload_dialog.dart`,
> `scripts_search_bar.dart`, `script_filter_sheet.dart`, `script_row_menus.dart`,
> `keyboard_shortcuts.dart`, `script_details_dialog.dart`).
>
> **Coverage contract cross-reference:** the e2e `flow_catalog.dart` (98 flows
> across 13 groups) was used as the inventory of user-facing flows so no major
> path was missed.

---

## 1. Methodology

1. **Inventory** — Read `integration_test/e2e/flow_catalog.dart` to enumerate
   every supported user flow (first-run, profile, keypair, account, scripts,
   downloads, canisters, dapps, vault, passkey, settings, shortcuts, deeplink).
2. **Read the source** of every screen and the widgets that compose each flow,
   tracing the exact callback chain (`onTap` → handler → dialog/route).
3. **Count interactions** — For each flow, count taps/clicks + keystrokes from
   the moment the user decides to do something to the moment the outcome is
   visible. A "click" is any discrete pointer tap or key press the user must
   intentionally perform (auto-focus, auto-fill, and persisted defaults do
   **not** count).
4. **Diff against shipped work** — Cross-checked every candidate against the
   already-completed QW-1..5, M-1/4/7/9, WU-1..9, WU-S1/S2, and the resolved
   UX-CRIT/UX-H items in `OPEN_ISSUES.md` so nothing here re-recommends
   shipped work.
5. **Score** — Impact × confidence ÷ effort. Effort: **S** (< 1 file, < 1 h),
   **M** (1–3 files or a new widget), **L** (cross-cutting / needs design call).
   Priority: **P0** (broken/dead-end), **P1** (high-frequency pain), **P2**
   (polish), **P3** (nice-to-have).

### What "already shipped" means here (do NOT redo)

| Shipped item | Where |
|---|---|
| Inline profile switcher (3→2 taps) | `profile_menu.dart` (WU-4) |
| "Run" SnackBarAction after download | `scripts_screen.dart` (WU-2) |
| "Share" SnackBarAction after create | `scripts_screen.dart` (WU-3) |
| `?` shortcuts help overlay | `keyboard_shortcuts.dart` (WU-6) |
| Category chip row below search | `scripts_screen.dart` (M-4) |
| Inline key-parameter in Add-Key sheet | `add_account_key_sheet.dart` (M-1) |
| QuickUpload smart defaults (desc/tags/category) | `quick_upload_dialog.dart` (M-7, QW-4) |
| Compact theme picker | `settings_screen.dart` (M-9) |
| Auto-focus / Enter-submits / default buttons / shortcut hints | QW-1..5 |
| Secure-storage readiness + gnome-keyring auto-start | wizard (WU-S1/S2) |
| Trust-dialog Enter/Esc, principal warning | `script_app_host.dart` (QW-5, UX-H4) |
| Recovery-code auto-check on Copy/Download | `recovery_codes_screen.dart` (QW-2) |
| Always-visible marketplace download button | `script_row_menus.dart` (QW-3) |
| Direct "Register @username" menu tile | `profile_menu.dart` |
| Ctrl+S save / R refresh / Esc back per screen | `keyboard_shortcuts.dart` (UX-9) |
| `←/→` + `Enter` in Details dialog | `script_details_dialog.dart` (UX-9) |
| Load-more pagination + "End of results" | `scripts_screen.dart` (UX-N2) |

---

## 2. Flow-by-flow analysis

### 2.1 First-run profile creation (`unified_setup_wizard.dart`)

**Path:** app open → wizard (auto) → display name (autofocus) → optional
username (Tab→Enter) → **Get Started** → ☑ success screen → **Start
Exploring** → post-registration security prompt (vault/passkey/skip) → app.

| Step | Interaction count |
|---|---|
| Type display name + Enter→next | ~2 keys |
| Type username (optional) | varies |
| Tap "Get Started" | 1 |
| Tap "Start Exploring" on success screen | **1 (eliminable)** |
| Pick Skip / vault / passkey | 1 |

**Pain point.** After `createProfile` + `registerAccount` succeed, the wizard
paints a **full-screen success view** (`_buildSuccessScreen`, line 603) whose
only control is "Start Exploring" (`Navigator.pop`, line 650). For an account
that just registered, the **next** thing the user sees is the
post-registration security prompt (`showPostRegistrationSecurityPrompt`,
line 914). So the celebratory success screen is a full-screen interstitial
between two real screens — a pure extra tap with no decision value.

**Optimization (CR-3).** Fold the success summary (checkmark + "profile +
account ready") into the **header** of the security prompt. Flow becomes
create → security choice → app. Saves 1 full-screen + 1 tap for every
registered-account onboarding.

---

### 2.2 Profile switching & management (`profile_menu.dart`)

**Path (≥2 profiles):** avatar → menu (inline list rendered) → tap target
profile. **2 taps.** Already optimal (WU-4).

**Path (1 profile):** avatar → "Switch Profile / Only you" tile → manage sheet.
Only path to rename/delete is the manage sheet's per-row `⋮` menu.

**Pain point (minor).** No keyboard shortcut to cycle the active profile.
Power users with several identities switch via 2 pointer taps every time.

**Optimization (CR-14, P3).** Bind `Ctrl+Shift+↑/↓` (or `Alt+P`) to cycle the
active profile when >1 exists, with a toast naming the new active profile.

---

### 2.3 Marketplace browse → download → run (`scripts_screen.dart` + details dialog)

Two download entry points exist; they have **different** click costs.

**(a) Direct from tile** (QW-3 always-visible Download icon → WU-2 Run
SnackBarAction): **2 taps**. Optimal.

**(b) Via the details dialog** (`_showScriptDetails` → onDownload):

| Step | Interactions |
|---|---|
| Tap tile → details dialog opens | 1 |
| Tap Download (or Enter, UX-9) | 1 |
| *dialog stays open*; Run SnackBar fires underneath | — |
| Dismiss the dialog (Esc / backdrop) to reach the SnackBar | **1 (eliminable)** |
| Tap "Run" on the SnackBar | 1 |

**Pain point (CR-1).** `_downloadScript` / `_installBundle` show the Run
SnackBar but **do not pop the details dialog** (`scripts_screen.dart:565`,
`:1020`). The SnackBar is rendered by the underlying scaffold and is
**obscured by the dialog route**, so the user must close the dialog before
the "Run" action is reachable. That is one extra tap *only on the dialog
path* — and the dialog path is the one new users take (they tap the tile to
"see what it is" before downloading).

**Optimization (CR-1, P1).** On a successful download initiated from the
details dialog, `Navigator.of(context).pop()` the dialog *first*, then show
the Run SnackBar. Collapses the dialog path **5 → 4** interactions and makes
the Run action immediately visible.

---

### 2.4 Script authoring (`script_creation_screen.dart`)

**Path:** FAB / `N` → creation screen → (template pre-selected) → edit title
→ edit code → **Create Script** → returns to list → "Publish" SnackBar.

**Pain points.**

1. **Template selector is expanded by default** (`_templatesExpanded = true`,
   line 62) and each card is 180 px tall (`Wrap` of 200×180 cards, line 250).
   On a typical viewport the selector + details form push the **code editor
   and the Create button below the fold**, forcing a scroll just to start
   editing. The template was already chosen for the user (first template
   pre-selected, line 91), so the grid is in the user's way more than it
   helps after first paint. *(CR-5)*
2. **Create-success SnackBar offers only "Publish"** (`scripts_screen.dart:1126`).
   For a freshly authored script the highest-frequency next action —
   especially for a scratch/test script — is **Run**, not Publish. *(CR-2)*
3. **No keyboard submit.** The title field uses `TextInputAction.next`; there
   is no "Enter to create" anywhere on the form. *(CR-11)*

**Optimizations.**
- **CR-5 (P2):** default-collapse the template selector (or relocate it
  *below* the editor) so the editor + Create button are above the fold.
- **CR-2 (P1):** add a "Run" `SnackBarAction` to the create-success SnackBar
  (keep "Publish" as a second action or swap primacy).
- **CR-11 (P2):** `Ctrl/Cmd+Enter` to create from anywhere on the form.

---

### 2.5 Publishing to the marketplace (`quick_upload_dialog.dart`)

**Path:** local row `⋮`/hover → Share to Marketplace → QuickUpload dialog
(title/desc/category/tags all pre-filled by M-7/QW-4, price defaults 0) →
**Upload to Marketplace**.

Already heavily streamlined by M-7 + QW-4. Two residuals remain:

1. **Tags are a comma-separated free-text field** (line 561). No validation,
   no chip UI, easy to fat-finger (trailing commas, spaces, typos). The rest
   of the marketplace surface uses chips. *(CR-9)*
2. The dialog hard-sizes to **90 % × 90 %** of the viewport (line 403) for
   what is, after pre-fill, a 5-field form. On desktop that is a lot of
   empty space.

**Optimization.** **CR-9 (P2):** replace the tags `TextFormField` with a
chip-input (type → Enter adds a chip; `×` removes). Reduces typos and
matches the chip vocabulary used on browse tiles. Optionally shrink the
dialog to a content-sized max (~600 px wide).

---

### 2.6 Marketplace search & filter (`scripts_search_bar.dart` + `script_filter_sheet.dart`)

**Search:** `/` or `Ctrl+F` focuses (DONE). Recent searches dropdown on focus.

**Filters:**
- **Category** — inline chip row below the bar (M-4, DONE): **1 tap**.
- **Sort / Downloaded-only / Favorites-only** — still inside the
  `FilterBottomSheet`: filter icon → sheet → (dropdown → option) or (chip) →
  optionally the ascending toggle. **3–5 interactions** for a sort change.
- **"Clear All"** only appears when `activeFilters.length > 1`
  (`scripts_search_bar.dart:88`) — a single active filter has no bulk-clear.

**Pain points.**
- M-4 inlined the **most** visual filter (category) but left the **most
  behavioural** one (sort) in a sheet. Users re-sort far more often than they
  re-categorize.
- Filter state is **inconsistent across restarts**: category persists
  (`_loadSavedCategory`, line 475) but `_allScriptsSortOption`,
  `_showDownloadedOnly`, `_showFavoritesOnly` reset to defaults on every cold
  start. (Noted as MEDIUM in the 2026-07-19 review; still unaddressed.)
  *(CR-6)*

**Optimizations.**
- **CR-8 (P1):** surface a compact **sort menu** (icon + current-sort label,
  opens a small popup) and two **toggle chips** (Downloaded, Favorites)
  inline next to the filter button. The bottom sheet is retained for the
  full category grid / reset; the three highest-frequency controls become
  1-tap. Sort change drops from **~4 → 1** interaction.
- **CR-6 (P2):** persist sort + downloaded/favorites alongside category in
  `SharedPreferences` (single helper) so a returning user sees their last
  view. Removes the inconsistency.
- **CR-7 (P2):** add `↑/↓` + `Enter` keyboard navigation to the
  recent-searches dropdown (currently mouse-only).

---

### 2.7 Dapp launch (`dapps_screen.dart` → `dapp_runner_screen.dart`)

**Path:** Dapps tab (`Alt+3`) → tap card → runner mounts → first canister call
→ trust dialog → Enter/Trust → dapp runs.

| Step | Interactions |
|---|---|
| Open tab + tap card | 2 |
| Trust dialog (Enter = Allow once) | 1 |
| **Total to a running mainnet dapp** | **3** |

Already good. Two minor residuals:

1. **Connection "Apply" is a manual button.** After editing the backend id /
   host (local-replica case), the user must tap **Apply** to remount
   (`_applyConfig`, line 210). `onFieldSubmitted` on either field does nothing.
   *(minor — could Enter-on-field apply.)*
2. The local-replica banner embeds `dfx` shell commands as **non-copyable
   prose** (`_kLocalReplicaBannerBody`, line 96). (Noted 2026-07-19 MEDIUM.)
   Making it a copyable code block (like the WU-S2 install command) removes
   a manual select-and-copy.

**Optimizations (both P3).** Wire `onFieldSubmitted` → `_applyConfig`; render
the banner's `dfx` command in a copyable `SelectableText` + copy button.

---

### 2.8 Vault credential entry — **N/A today**

`VaultPasswordSetupScreen` creates the vault with `plaintext: '{}'`
(`vault_password_setup_screen.dart:124,132`) and `VaultUnlockScreen` only
**decrypts** the blob. There is **no screen to add, edit, or view credentials
inside the vault** — the zero-knowledge store is shipped empty with no
data-entry surface.

> The task brief asks to "streamline the add-credential flow". That flow does
> not exist yet. This is flagged as an **architectural gap (CR-12)**, not a
> click-reduction opportunity, because there is nothing to reduce.

The setup/unlock flows themselves are already lean (autofocus, Enter submits,
strength meter, recovery-code entry). The recovery-codes screen is also
already optimal after QW-2 (Copy/Download auto-checks the gate).

---

### 2.9 Settings (`settings_screen.dart`)

Theme is a compact `SegmentedButton` (M-9). Sections are logically grouped
(Help / Appearance / Links / About / hidden Developer). No click-reduction
defects remain. Developer-options unlock is intentionally gated at 7 taps
(easter-egg; correct). **No recommendations.**

---

### 2.10 Download history (`download_history_screen.dart`)

**Path to run from history:** Scripts `⋮` → Download History → tap row →
runs. **3 taps** (2 to enter, 1 to run).

**Pain point (CR-4).** Each row's trailing widget is a `PopupMenuButton` with
exactly **one** item ("Remove from history", line 342). A single-item popup
is a pointer tap to open a menu whose only choice then needs a second tap,
followed by the confirm dialog. A direct `IconButton(Icons.delete_outline)`
opening the same confirm dialog saves a tap and matches the destructive-icon
convention used elsewhere.

**Optimization (CR-4, P2).** Replace the 1-item popup with a direct trash
`IconButton`; sweep the codebase for other 1-item `PopupMenuButton` patterns
and apply the same fix.

---

### 2.11 Passkey management (`passkey_management_screen.dart`)

**Path:** avatar → My Account → scroll to Security → Passkeys → **Manage**
(OutlinedButton) → screen → FAB **Add Passkey**.

**Cost to "Add a passkey" from the shell: ~5 taps** (open menu, My Account,
scroll, Manage, FAB). Vault, by contrast, has a **direct tile in the profile
menu** when the account is registered (`profile_menu.dart:247`). Passkeys do
not — they are reached only through My Account → Security.

**Pain point (CR-13).** On platforms where `PasskeyPlatform.isSupported` is
true (macOS/Windows/Android/Web), passkeys are a first-class security
primitive but are buried 3 levels deep. On Linux desktop they are honestly
disabled, so the burying is accidental rather than intentional.

**Optimization (CR-13, P3).** When `PasskeyPlatform.isSupported`, render a
direct "Passkeys" `_MenuTile` in the profile menu (next to Vault), mirroring
the vault tile. Drops add-passkey-from-shell from ~5 → 3 taps. (Keep the
Account → Security entry as the secondary path.)

---

### 2.12 Keypair label editing (`account_profile_screen.dart`)

**Path:** tap the label row → `_EditKeyLabelDialog` (`showDialog`) → type →
Save → dialog closes.

**Pain point (CR-10).** Renaming a label opens a **modal dialog** for a
single text field. The label row already shows an edit affordance icon
(line 623). In-place editing (tap → text becomes an inline `TextField` →
Enter saves / Esc cancels) removes the dialog round-trip entirely and matches
the "click text to rename" convention users expect.

**Optimization (CR-10, P2).** Inline-editable label; reserve the dialog only
for the multi-field cases.

---

## 3. Prioritized recommendations

| ID | Recommendation | Flow impact | Before → After | Effort | Priority |
|----|----------------|-------------|----------------|--------|----------|
| **CR-1** | Auto-close Details dialog on download success; surface Run SnackBar above the now-visible list | Marketplace download (dialog path) | 5 → 4 | S | **P1** |
| **CR-2** | Add "Run" SnackBarAction to create-success SnackBar (today: Publish only) | Script authoring | Run-after-create 3 → 1 | S | **P1** |
| **CR-3** | Fold wizard success screen into the post-reg security prompt header | First-run onboarding | −1 full screen + −1 tap | S | **P1** |
| **CR-8** | Inline Sort menu + Downloaded/Favorites toggle chips next to search | Marketplace filter | Sort change ~4 → 1 | M | **P1** |
| **CR-5** | Default-collapse the template selector (or move below editor) | Script authoring | Editor above the fold | S | P2 |
| **CR-6** | Persist sort + downloaded/favorites across restarts (match category) | Marketplace filter | Consistency | S | P2 |
| **CR-9** | Chip-based tag editor in QuickUpload (replace comma text) | Publishing | Fewer typos | M | P2 |
| **CR-10** | Inline-editable keypair label (replace rename dialog) | Account/keys | −1 dialog | M | P2 |
| **CR-4** | Replace 1-item PopupMenuButton with direct IconButton (Download History et al.) | Several | −1 tap each | S | P2 |
| **CR-7** | `↑/↓`+Enter keyboard nav for recent-searches dropdown | Search | Keyboard-only reachable | S | P2 |
| **CR-11** | `Ctrl/Cmd+Enter` to create on the script-creation form | Script authoring | Keyboard submit | S | P2 |
| **CR-13** | Direct "Passkeys" menu tile when `PasskeyPlatform.isSupported` | Passkey enrollment | ~5 → 3 taps | M | P3 |
| **CR-14** | `Ctrl+Shift+↑/↓` to cycle active profile (>1 profile) | Profile switch | Keyboard-only | S | P3 |
| **CR-12** | **Architectural:** build a vault credential-entry UI (vault is empty `'{}'` today) | Vault (new surface) | New capability | L | P2 (needs decision) |

---

## 4. Quick wins (S, ship immediately)

These five are each < 1 h, single-file, and touch high-frequency paths:

1. **CR-1 — Close the details dialog on download.** One `Navigator.pop`
   before the Run SnackBar in `_downloadScript`/`_installBundle`. The Run
   action becomes immediately actionable instead of hidden behind the dialog.
2. **CR-2 — "Run" on the create SnackBar.** One `SnackBarAction` in
   `_showCreateSheet`'s success SnackBar (`scripts_screen.dart:1126`).
3. **CR-3 — Collapse the wizard success screen.** Replace `_buildSuccessScreen`
   with routing straight into the security prompt (whose header absorbs the
   checkmark + "ready" copy), then back to the app on resolve.
4. **CR-5 — Default-collapse the template selector.** Flip
   `_templatesExpanded` to `false`; the editor + Create button land above the
   fold. Power users still expand to switch templates.
5. **CR-4 — Kill the 1-item popup menu.** Download-History row → direct trash
   `IconButton`; audit for other single-item `PopupMenuButton`s.

---

## 5. Medium-term improvements (M)

- **CR-8 — Inline sort + source toggles.** New compact widget beside the
  search bar; the bottom sheet stays for the full category grid + Reset. The
  single biggest filter-friction win remaining after M-4.
- **CR-9 — Chip tag editor.** Replace the comma-separated `TextFormField`
  with a chip-input in `QuickUploadDialog`; reuse the marketplace chip
  vocabulary.
- **CR-10 — Inline keypair label.** In-place `TextField` swap on the label
  row of `account_profile_screen.dart`; dialog reserved for multi-field edits.
- **CR-13 — Passkeys menu tile** on supported platforms (mirrors the existing
  Vault tile).

---

## 6. Architectural UX changes (L — needs human decision)

- **CR-12 — The vault has no credential surface.** `VaultPasswordSetupScreen`
  creates `'{}'`; `VaultUnlockScreen` decrypts; **nothing adds or renders
  stored credentials.** Before any "streamline credential entry" work is
  meaningful, the product must decide: (a) what the vault stores (IC
  identities? arbitrary secrets? canister-specific keys?), (b) the entry/edit
  UI shape, (c) how it stays compatible with the zero-knowledge contract
  (client-side encrypt-on-write). This is a feature-design decision, not a
  click-reduction tweak — flagged here per `AGENTS.md` "Architectural issues
  require human decision".

---

## 7. Risks & guardrails

- **CR-1 / CR-2** change SnackBar timing relative to route pops — must keep
  the existing `mounted` guards and use a captured `ScaffoldMessenger` (the
  pattern already used in `_buyScript`) so the bar isn't lost when the dialog
  route pops.
- **CR-3** must preserve the "deliberate dismissal remembered" semantics
  (`_firstRunWizardDismissedKey`) and the local-only skip path (no account →
  no security prompt).
- **CR-8** must not regress the existing `activeFilterCount` badge contract
  or the e2e `scripts.filter_*` flows (which drive the bottom sheet).
- **CR-6** filter persistence must not persist a state whose backing data no
  longer exists (e.g. favorites-only when favorites were cleared on another
  screen) — re-validate on load.
- Every change ships with its gating widget test (AGENTS.md "Write Failing
  Tests" first) and passes the relevant `just test-feature <name>`.

---

## 8. Top 10 recommendations (summary, by priority)

1. **CR-1** — Auto-close Details dialog on download so the Run SnackBar is
   actionable (S, P1).
2. **CR-8** — Inline Sort + Downloaded/Favorites toggles beside search (M, P1).
3. **CR-2** — "Run" SnackBarAction on script create (S, P1).
4. **CR-3** — Collapse the wizard success screen into the security prompt (S, P1).
5. **CR-5** — Default-collapse the template selector so the editor is visible (S, P2).
6. **CR-6** — Persist sort + source filters across restarts (S, P2).
7. **CR-9** — Chip-based tag editor in QuickUpload (M, P2).
8. **CR-10** — Inline-editable keypair label (M, P2).
9. **CR-4** — Replace single-item popup menus with direct IconButtons (S, P2).
10. **CR-12** — Decide + build the vault credential-entry surface (L, needs decision).
