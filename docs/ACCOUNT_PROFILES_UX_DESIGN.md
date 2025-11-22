# Account Profiles - Frontend UX Design

**Version:** 2.0
**Status:** Implemented
**Created:** 2025-11-17
**Updated:** 2025-11-21

## Overview

This document defines the user experience design for **Profile Management** in the ICP Autorun Flutter app. It builds upon `ACCOUNT_PROFILES_DESIGN.md` (backend specification) and focuses on creating a professional, intuitive UX.

## Architecture Note: Profile-Centric Model

**CRITICAL:** This app uses a **browser profile** mental model:
- Each **Profile** is like a Chrome/Firefox profile - completely isolated
- Each profile contains 1-10 **keypairs** (cryptographic keys)
- Each profile maps to exactly ONE backend **account** (@username)
- Keypairs belong to ONE profile only - NO key sharing across profiles
- Tree structure: Profile → Keypairs (not a graph)

### Signing Key Concept

**Every profile has one "signing key"** (also called "primary keypair" or "active keypair"):
- This is the keypair currently used for all cryptographic operations
- Used to sign: add key, remove key, update profile, upload scripts
- Displayed on profile cards as the "signing principal"
- User can switch which keypair is the signing key via "Use for signing" button
- The signing key MUST be registered with the backend account to perform operations

**Incognito Profiles:**
- At least one profile without a registered account should always be available
- Allows users to interact with the app anonymously
- Can upload scripts and perform operations without account registration
- User can choose to register the profile later if desired

## Core UX Principles

1. **Progressive Disclosure**: Don't overwhelm users with cryptographic details upfront
2. **Clear Visual Hierarchy**: Important actions prominent, dangerous actions protected
3. **Real-time Feedback**: Immediate validation and status updates
4. **Graceful Onboarding**: Smooth transition from keypair → account
5. **Trust Through Transparency**: Show security details when users need them
6. **Fail Fast, Fail Clear**: Errors are explicit with actionable guidance

## Implementation Status (2025-11-21)

### ✅ Fully Implemented (Backend + Frontend)

**Backend API** - All account endpoints fully operational:
- Account registration, retrieval (by username/public key), and profile updates
- Public key add/remove operations with signature verification
- Admin operations (key disable, recovery key addition)
- Comprehensive security (replay prevention, IC principal derivation, audit trails)

**Frontend Core Flows:**
- Profile list & creation with empty states and active profile management
- Profile switching (tap card to switch, visual feedback with ACTIVE badge)
- Profile menu (three-dot menu with View/Register/Delete options)
- Profile cards show signing principal and "(incognito)" label for unregistered profiles
- Account profile screen with editable fields, key management, and mismatch warnings
- Signing key concept: One keypair per profile used for all operations
- Signing key switching: "Use for signing" button to change active keypair
- Signing key badge: Visual indicator showing which key is currently signing
- Auto-recovery from key mismatch: Automatically registers signing key if recoverable
- Unlink account functionality: Clear username without deleting backend account
- Add key workflow (generate new keypairs per profile and register with backend)
- Remove key workflow with confirmations and last-key protection
- Key details sheet with copy-to-clipboard and danger-zone actions
- Profile-centric controllers enforcing 1 profile → 1 account model

**Account Registration:**
- Single-page form with real-time username validation
- All profile fields (display name, bio, contacts)
- Backend integration with signature verification
- Auto-routes from profile creation (can skip to stay incognito)

## User Flows

### Flow 1: First-Time User (No Profile)

```
1. Launch App
   ↓
2. Empty State: "Create your first profile"
   ↓
3. Create Profile Wizard
   - Choose algorithm (Ed25519 recommended)
   - Set profile name (local label)
   - Save mnemonic securely
   - AUTOMATICALLY registers backend account (@username)
   ↓
4. Home screen with profile
```

**NOTE:** Profile creation IMMEDIATELY creates:
- Local profile with initial keypair
- Backend account (@username)
- 1:1 relationship established

### Flow 2: Create Additional Profile

```
1. Profile List Screen
   ↓
2. Tap "+" FAB button
   ↓
3. Create Profile Dialog:
   - Choose algorithm (Ed25519 recommended)
   - Set profile name (optional)
   - Save mnemonic securely
   ↓
4. Profile created with initial keypair
   ↓
5. Automatically navigate to Account Registration Form
   ↓
6. User can register (@username) OR skip to use incognito
```

### Flow 2b: Switch Active Profile

```
1. Profile List Screen
   ↓
2. Tap any profile card (not already active)
   ↓
3. Profile becomes active immediately
   ↓
4. Snackbar: "{Profile Name} is now active"
   ↓
5. Visual update: Card gains border, elevation, "ACTIVE" badge
```

### Flow 3: Account Registration

```
1. Single-page form with:
   - Username input with real-time validation
   - Visual feedback:
     ✓ Available (green checkmark)
     ✗ Taken (red X)
     ⚠ Invalid format (orange warning)
   - Format rules shown below input
   - Display name and optional contact fields
   - "Register" button
   ↓
2. Submit signed request to backend
   ↓
3. Return to account profile on success
```

### Flow 4: Add Keypair to Current Profile

```
1. Profile Screen
   ↓
2. Tap "Add Key" (floating action button)
   ↓
3. Confirm Dialog: "Generate New Keypair"
   - Explain: "This will create a new device key for this profile"
   - Show: "Your profile will have X/10 keys"
   ↓
4. Generate NEW keypair
   - Same algorithm as profile's existing keys
   - Derive IC principal
   ↓
5. Sign operation with current active key
   ↓
6. Success: Key added to profile
   - Save locally AND register with backend
   - Update UI immediately
```

**IMPORTANT CHANGE:**
- REMOVED: "Use existing keypair" option (NO cross-profile key usage)
- REMOVED: "Import public key manually" option (keys are generated, not imported)
- Keys are GENERATED for the current profile, not imported from elsewhere

### Flow 5: Change Signing Key

```
1. Account Profile → Key List
   ↓
2. Tap "Use for signing" button on an active key
   ↓
3. Profile's signing key switches immediately
   ↓
4. Snackbar: "Signing key updated"
   ↓
5. UI updates: New key gets "SIGNING KEY" badge, old badge removed
```

### Flow 6: Signing Key Mismatch Recovery

**Scenario**: Profile's signing key is not registered with the account

```
IF another key in profile IS registered:
  1. Warning banner appears: "Signing Key Not Registered"
  2. System automatically registers signing key using registered key to sign
  3. Toast: "Registered your signing key with account"
  4. Banner disappears

IF NO keys in profile are registered:
  1. Warning banner appears: "Signing Key Not Registered"
  2. Banner shows: "You need to recover the original signing key or unlink this account"
  3. User taps "Unlink Account" button
  4. Confirmation dialog explains account stays on marketplace
  5. Profile.username cleared, can re-register later
```

### Flow 7: Remove Public Key

```
1. Account Profile → Key List
   ↓
2. Swipe left on key OR tap menu
   ↓
3. "Remove Key" option (disabled if last active key)
   ↓
4. Confirmation Dialog
   - Warning: "This key will no longer have access"
   - Show key details
   - Show disabled date will be set
   - Cannot be undone (soft delete)
   ↓
5. Sign operation
   ↓
6. Success: Key marked inactive
   - Visual indication in list
   - Show disabled timestamp
```

## Screen Designs

### 1. Profile List Screen

**Layout**:
```
┌─────────────────────────────┐
│ Profiles        [Refresh]   │ ← App bar
├─────────────────────────────┤
│                             │
│ ┌─────────────────────────┐│
│ │ 👤 Alice          [⋮]  ││ ← Profile card with menu
│ │ @alice                  ││ ← Backend username
│ │ 🔑 aaaaa-aa...          ││ ← Signing principal
│ │ 3 keys • ACTIVE         ││ ← Key count + active badge
│ └─────────────────────────┘│
│                             │
│ ┌─────────────────────────┐│
│ │ 👤 Bob (incognito) [⋮] ││ ← Incognito profile
│ │ 🔑 bbbbb-bb...          ││ ← Signing principal
│ │ 1 key                   ││ ← Key count
│ └─────────────────────────┘│
│                             │
│                        [+]  │ ← FAB: Create profile
└─────────────────────────────┘
```

**Profile Card Menu** (tap ⋮):
```
┌─────────────────────────────┐
│     Alice                   │
├─────────────────────────────┤
│ 👤 View Account             │ ← If username exists
│    @alice                   │
├─────────────────────────────┤
│ ➕ Register Account         │ ← If username is null
│    Create @username for     │
│    this profile             │
├─────────────────────────────┤
│ 🗑️ Delete                  │ ← Red text
└─────────────────────────────┘
```

**Interactions**:
- **Tap card body**: Switch to this profile (if not already active)
- **Tap menu (⋮)**: Show profile actions menu
- **Tap refresh**: Reload all accounts from backend
- **Tap FAB (+)**: Create new profile
- **Active profile**: Shows elevated card with border and "ACTIVE" badge
- **Incognito profiles**: Show "(incognito)" label if no username

### 2. Account Registration Form

Single-page form layout:
```
┌─────────────────────────────┐
│ ← Back  Create Account      │
├─────────────────────────────┤
│                             │
│ Username                    │
│ ┌─────────────────────────┐│
│ │ alice              ✓    ││ ← Real-time validation
│ └─────────────────────────┘│
│                             │
│ • 3-32 characters           │
│ • Lowercase letters/numbers │
│ • Can use _ or -            │
│                             │
│ Display Name                │
│ ┌─────────────────────────┐│
│ │ Alice Developer         ││
│ └─────────────────────────┘│
│                             │
│ [Optional contact fields]   │
│                             │
│         [Register]          │
│                             │
└─────────────────────────────┘
```

### 3. Account Profile Screen

**Layout**:
```
┌─────────────────────────────┐
│ ← Account Profile  [Refresh]│
├─────────────────────────────┤
│ ⚠️ SIGNING KEY NOT REGISTERED│ ← Warning (if mismatch)
│ [Switch Key] or [Unlink]    │
├─────────────────────────────┤
│      👤                     │
│   Alice Developer           │ ← Display name (editable)
│     @alice                  │
│ Created: Nov 17, 2024       │
├─────────────────────────────┤
│ PROFILE                     │
│ ┌─────────────────────────┐│
│ │ Display Name *          ││ ← Editable fields
│ │ Email                   ││
│ │ Telegram                ││
│ │ Twitter/X               ││
│ │ Discord                 ││
│ │ Website                 ││
│ │ Bio                     ││
│ │    [Save Changes]       ││
│ └─────────────────────────┘│
├─────────────────────────────┤
│ PUBLIC KEYS          3/10   │
├─────────────────────────────┤
│ 🟢 0x1234...abcd           │ ← Active key
│    ✏️ SIGNING KEY          │ ← Signing badge
│    Principal: aaa...        │
│    Added: 2 days ago        │
│    [View] [Remove]          │
├─────────────────────────────┤
│ 🟢 0x5678...efgh           │
│    Principal: bbb...        │
│    Added: 1 day ago         │
│    [Use for signing] [View] │ ← Switch signing key
│    [Remove]                 │
├─────────────────────────────┤
│ 🔴 0x9012...ijkl           │ ← Disabled key
│    Principal: ccc...        │
│    Disabled: today          │
│    [View]                   │
│                             │
│                        [+]  │ ← FAB: Add key
└─────────────────────────────┘
```

**Key Features**:
- **Mismatch Warning**: Red banner at top if signing key not registered
  - Auto-recovers if possible (another key registered)
  - Shows manual actions if not recoverable
- **Editable Profile Section**: All account fields editable with save button
- **Signing Key Badge**: Current signing key shows "✏️ SIGNING KEY" badge
- **Use for Signing Button**: Appears on active keys (except current signing key)
- **Key Status**: 🟢 Active, 🔴 Disabled with appropriate actions
- **Last Active Protection**: Cannot remove last active key
- **Tap key card**: Opens full details in bottom sheet

### 4. Add Keypair Dialog

**Layout**:
```
┌─────────────────────────────┐
│                          ✕  │
│ Generate New Keypair        │
├─────────────────────────────┤
│                             │
│ This will create a new      │
│ cryptographic keypair for   │
│ this profile.               │
│                             │
│ Current keys: 2/10          │
│                             │
│ Algorithm: Ed25519          │
│ (matches your profile)      │
│                             │
│ The new key will be saved   │
│ securely on this device and │
│ registered with your account│
│                             │
│    [Cancel]  [Generate]     │
│                             │
└─────────────────────────────┘
```

**IMPORTANT CHANGES:**
- REMOVED: "Use Local Keypair" option (NO cross-profile key usage)
- REMOVED: "Import Public Key" option (keys are generated, not imported)
- SIMPLIFIED: Single action - generate new keypair for current profile
- Keypairs are created fresh, not imported from elsewhere

### 5. Key Details Sheet

**Layout**:
```
┌─────────────────────────────┐
│                          ✕  │
│ Public Key Details          │
├─────────────────────────────┤
│                             │
│ Status: 🟢 Active           │
│                             │
│ Public Key                  │
│ 0x1234567890abcdef...       │
│ [Copy Full Key]             │
│                             │
│ IC Principal                │
│ aaaaa-aa-aaaaa-aaaaa-cai    │
│ [Copy Principal]            │
│                             │
│ Added: Nov 17, 2024 10:00   │
│ Added by: 0x5678...         │
│                             │
│ ┌─────────────────────────┐│
│ │ [Remove This Key]       ││ ← Danger zone
│ └─────────────────────────┘│
│                             │
└─────────────────────────────┘
```

### 6. Key Mismatch Warning Banner

**Scenario 1: Recoverable (another key registered)**
```
┌─────────────────────────────┐
│ ⚠️ Auto-Recovering          │
├─────────────────────────────┤
│ Your signing key wasn't     │
│ registered. We're fixing    │
│ this now...                 │
│                             │
│ [Spinner]                   │
└─────────────────────────────┘
```
After auto-recovery:
```
Toast: "✓ Registered your signing key with account"
```

**Scenario 2: Not Recoverable (no keys registered)**
```
┌─────────────────────────────┐
│ ⚠️ Signing Key Not Registered│
├─────────────────────────────┤
│ Your profile's signing key  │
│ is not registered with this │
│ account. You need to recover│
│ the original signing key or │
│ unlink this account.        │
│                             │
│     [Unlink Account]        │
└─────────────────────────────┘
```

### 7. Delete Profile Confirmation

```
┌─────────────────────────────┐
│ Delete Profile              │
├─────────────────────────────┤
│ Are you sure you want to    │
│ delete "Alice"?             │
│                             │
│ This will permanently       │
│ delete the profile and all  │
│ its keypairs. This action   │
│ cannot be undone.           │
│                             │
│   [Cancel]   [Delete]       │
└─────────────────────────────┘
```

## Visual Design System Integration

### Colors (from AppDesignSystem)

**Account Status Indicators**:
- ✓ Has Account: `AppDesignSystem.accentColors.teal`
- ⚠ No Account: `AppDesignSystem.warning`
- 🟢 Active Key: `AppDesignSystem.success`
- 🔴 Disabled Key: `AppDesignSystem.error`

**Buttons**:
- Primary action: Gradient (indigo → violet)
- Secondary: Outlined with primary color
- Danger: Error color

**Cards**:
- Background: Surface color
- Elevation: 2-4
- Border radius: 12px
- Padding: 16px

### Typography

- **Screen titles**: `headlineMedium` (28sp, bold)
- **Section headers**: `titleMedium` (16sp, semibold)
- **Body text**: `bodyMedium` (14sp, regular)
- **Captions**: `bodySmall` (12sp, light)
- **Usernames**: `titleLarge` (22sp, bold, accent color)

### Spacing

- Screen padding: 16px
- Card spacing: 12px
- Section gaps: 24px
- Button height: 48px

## Interaction Patterns

### Username Validation (Real-time)

**States**:
1. **Empty**: Placeholder text, no validation
2. **Typing**: Debounced validation (500ms after last keystroke)
3. **Validating**: Show spinner
4. **Valid**: Green checkmark + "Available"
5. **Invalid Format**: Orange warning + format hint
6. **Taken**: Red X + "Already taken" + suggestions
7. **Reserved**: Red X + "Reserved username"

**Implementation**:
- Use `debounce` to avoid excessive API calls
- Cache validation results
- Show validation below input field
- Disable "Continue" if invalid

### Key Status Visualization

**Signing Key** (profile's active keypair):
- Green status dot
- "✏️ SIGNING KEY" badge
- Cannot remove (primary auth method)
- Used for all cryptographic operations

**Active Key** (registered but not signing):
- Green status dot
- Full brightness
- Shows "Use for signing" button
- Can be removed if not last active key

**Disabled Key**:
- Red status dot
- Reduced opacity (0.6)
- No remove action
- Show disabled timestamp

**Last Active Key Protection**:
- Green status dot
- Badge: "LAST ACTIVE" (if only active key besides signing key)
- Disable remove button to prevent lockout

### Profile Switching

**Interaction**:
1. User taps any profile card body (not the menu)
2. If already active: No action
3. If different profile:
   - Profile becomes active immediately
   - Card gains border, elevation, "ACTIVE" badge
   - Previous active profile loses active styling
   - Snackbar: "{Profile Name} is now active"
   - All subsequent operations use this profile's signing key

### Signing Key Switching

**Interaction**:
1. User taps "Use for signing" button on an active key
2. Profile's signing key switches immediately (no confirmation)
3. UI updates:
   - New key gains "✏️ SIGNING KEY" badge
   - Old signing key loses badge, shows "Use for signing" button
4. Snackbar: "Signing key updated"
5. All future operations use the new signing key

### Auto-Registration of a Key

**Scenario**: Currently selected keypair is not registered with account

**Automatic Registration** (if another profile key of the same account IS registered):
1. Warning banner appears: "➕ Registering Key"
2. System uses registered key to sign "add key" request
3. Signing key is registered with backend account
4. Banner disappears
5. Toast: "✓ Registered your signing key with account"

**Manual Registration** (if NO profile keys are registered):
1. Warning banner appears with explanation
2. User may choose: "Register Account"

### Loading States

**Account Registration**:
- Show loading spinner during submission
- Display error message on failure with retry option

**Add/Remove Key**:
- Optimistic update (immediate UI change)
- Show subtle spinner
- On error: Rollback + show snackbar

### Error Handling

Errors are displayed using standard snackbars and inline form validation with clear, actionable messaging.

## Accessibility

### Screen Reader Support
- Semantic labels for all interactive elements
- Announce status changes (key added/removed)
- Proper focus management in forms and dialogs

### Keyboard Navigation
- Tab through form fields
- Enter to submit
- Escape to close sheets/dialogs

### Visual Accessibility
- Sufficient color contrast (WCAG AA)
- Don't rely on color alone (use icons + text)
- Large touch targets (48x48dp minimum)

## Animations

### Micro-interactions
- Button press: Scale 0.95 (100ms)
- Card tap: Ripple effect
- Success: Checkmark animation
- Error: Shake animation

### Transitions
- Sheet open/close: Slide up/down
- List items: Fade in with stagger

### Loading
- Circular progress for operations
- Skeleton screens for data loading

## Performance Considerations

### Caching Strategy
- Cache account data for 5 minutes
- Refresh on pull-to-refresh
- Invalidate on account operations

### Optimistic Updates
- Add key: Show in list immediately, rollback on error
- Remove key: Mark inactive immediately, rollback on error
- Registration: Only show success after server confirms

### Lazy Loading
- Load full account details only when viewing profile
- Load key list on-demand
- Paginate if >10 keys (unlikely but possible)

## Security UX

### Key Visibility
- Public keys: Show first 6 and last 4 characters by default
- Tap to expand full key
- Copy button for full key
- Never show private keys in account screens

### Signature Transparency
- Show "Signing..." toast when generating signatures
- Log all signed operations locally for user audit
- Explain what's being signed in confirmation dialogs

### Confirmation Dialogs
- Remove key: Require explicit confirmation
- Show impact of action
- Cannot be undone messaging

## Open UX Issues & Future Enhancements

### Identified During Design

1. **Profile-Account Relationship** ✅ RESOLVED:
   - Design: 1 profile → 1 account (enforced)
   - Profiles are isolated (like browser profiles)
   - No need for account switcher (use profile switcher)

2. **Key Labeling**:
   - Users may want to label keys: "Mobile", "Desktop", "Hardware Wallet"
   - Backend doesn't support key labels (metadata)
   - Workaround: Store labels locally in app

3. **Account Recovery Flow**:
   - Admin recovery requires out-of-band verification
   - UX: How to guide users to support?
   - Need clear "Lost All Keys?" help flow

4. **Username Change**:
   - Design doesn't support username changes
   - Users will want this
   - Future enhancement needed

5. **Account Deletion**:
   - Design intentionally omits account deletion
   - Users expect to be able to delete accounts
   - Need clear communication: "Accounts are permanent for audit trail"

6. **Multi-Device Sync**:
   - Keypairs are stored locally (secure storage)
   - If user adds key from another device, how to import?
   - QR code import flow? Manual key import?

7. **Transaction History**:
   - Backend stores signature_audit
   - Should we show this to users?
   - "Activity Log" showing all account operations

8. **Security Settings**:
   - No timeout/expiry for keys
   - Should there be "require re-auth for sensitive ops"?
   - Biometric confirmation before key operations?

9. **Onboarding Education**:
    - Concepts are complex: keypair vs account vs principal vs key
    - Need better educational content
    - Tooltips, help dialogs, onboarding tutorial

### Nice-to-Have Features

- **QR Code Sharing**: Generate QR code for public key
- **Key Import/Export**: Backup/restore keys via encrypted file
- **Social Recovery**: Nominate trusted contacts for account recovery
- **Hardware Key Support**: WebAuthn integration
- **Key Rotation Reminders**: Notify users to rotate keys periodically
- **Risk Scoring**: Show account security score based on key count/age

## Testing Requirements

### Manual Testing Checklist

- [ ] Registration wizard: Single-screen MVP registers an account and routes back to ProfileHomePage
- [ ] Username validation: Real-time feedback works
- [ ] Reserved usernames: Properly rejected
- [ ] Duplicate username: Proper error shown
- [ ] Invalid characters: Proper validation
- [ ] Add key: Profile-generated flow works (AddAccountKeySheet + AccountController)
- [ ] Manual import paths: Not exposed (fail-fast per profile-centric rules)
- [ ] Remove key: Confirmation required
- [ ] Remove last key: Blocked with message
- [ ] Disabled key: Shows in list with proper styling
- [ ] Error states: All error messages clear
- [ ] Loading states: No UI jank
- [ ] Dark mode: All screens look good
- [ ] Small screen: No overflow or clipping
- [ ] Large screen: Proper layout
- [ ] Screen reader: All elements accessible
- [ ] Animations: Smooth and performant

### Automated Testing

- Widget tests for all new screens
- Integration tests for registration flow
- Integration tests for key management
- Error scenario tests
- Signature generation tests

## Future Enhancements

**UX Polish:**
- Add swipe gestures for key management
- Improve visual transitions and micro-interactions

**Accessibility:**
- Screen reader scripts and keyboard navigation testing
- Audit color contrast and touch target sizes
