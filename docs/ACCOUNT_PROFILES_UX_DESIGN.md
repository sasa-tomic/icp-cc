# Account Profiles - Frontend UX Design

**Version:** 1.2
**Status:** Implementation In Progress
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
- Account profile screen with editable fields, key management, and mismatch warnings
- Add key workflow (generate new keypairs per profile and register with backend)
- Remove key workflow with confirmations and last-key protection
- Key details sheet with copy-to-clipboard and danger-zone actions
- Profile-centric controllers enforcing 1 profile → 1 account model

### ✅ Account Registration

**Account Registration Wizard:**
- Single-page form with real-time username validation
- All profile fields (display name, bio, contacts)
- Backend integration with signature verification

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
2. Tap "Add Profile" button
   ↓
3. Create Profile Wizard (same as Flow 1)
   ↓
4. New profile created (isolated from existing profiles)
```

**REMOVED:** "Upgrade to Account" flow - profiles are ALWAYS accounts

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

### Flow 5: Remove Public Key

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
│ Profiles              [+]   │ ← App bar
├─────────────────────────────┤
│                             │
│ ┌─────────────────────────┐│
│ │ 👤 Alice                ││ ← Profile card
│ │ @alice                  ││ ← Backend username
│ │ 3 keys • Ed25519        ││ ← Key count + algorithm
│ │ aaaaa-aa... (primary)   ││ ← Primary principal
│ └─────────────────────────┘│
│                             │
│ ┌─────────────────────────┐│
│ │ 👤 Bob                  ││
│ │ @bob                    ││
│ │ 1 key • Ed25519         ││
│ │ bbbbb-bb... (primary)   ││
│ └─────────────────────────┘│
│                             │
└─────────────────────────────┘
```

**Key Changes**:
- REMOVED: "No Account" state (profiles are ALWAYS accounts)
- REMOVED: "Register Account" button (registration happens during profile creation)
- Focus on PROFILE as primary concept, not individual keys
- Show key count per profile
- Tap profile → Manage profile keys, Edit profile, Delete profile

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
│ ← Account Profile           │
├─────────────────────────────┤
│                             │
│      👤                     │
│     @alice                  │
│ Created: Nov 17, 2024       │
│                             │
│ ┌─────────────────────────┐│
│ │ PUBLIC KEYS        3/10 ││ ← Section header
│ ├─────────────────────────┤│
│ │ 🟢 0x1234...abcd       ││ ← Active key
│ │    Principal: aaa...    ││
│ │    Added: Nov 17, 10:00 ││
│ │    [View] [Remove]      ││
│ ├─────────────────────────┤│
│ │ 🟢 0x5678...efgh       ││
│ │    Principal: bbb...    ││
│ │    Added: Nov 17, 10:05 ││
│ │    [View] [Remove]      ││
│ ├─────────────────────────┤│
│ │ 🔴 0x9012...ijkl       ││ ← Disabled key
│ │    Principal: ccc...    ││
│ │    Disabled: Nov 17     ││
│ └─────────────────────────┘│
│                             │
│              [+]            │ ← FAB: Add key
└─────────────────────────────┘
```

**Features**:
- List all keys (active + inactive)
- Visual status: 🟢 Active, 🔴 Disabled
- Show IC principal for each key
- Timestamps for added/disabled
- Tap key → show full details
- Swipe to remove (if not last active)
- Show key count: "3/10" (current/max)

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

**Active Key**:
- Green status dot
- Full brightness
- All actions available

**Disabled Key**:
- Red status dot
- Reduced opacity (0.6)
- No remove action
- Show disabled timestamp

**Last Active Key**:
- Green status dot
- Badge: "Last Active" (cannot remove)
- Disable remove button

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
