# Account Profiles - Frontend UX Design

**Version:** 1.0
**Status:** Implementation Ready
**Created:** 2025-11-17

## Overview

This document defines the user experience design for Account Profiles in the ICP Autorun Flutter app. It builds upon `ACCOUNT_PROFILES_DESIGN.md` (backend specification) and focuses on creating a professional, intuitive UX.

## Core UX Principles

1. **Progressive Disclosure**: Don't overwhelm users with cryptographic details upfront
2. **Clear Visual Hierarchy**: Important actions prominent, dangerous actions protected
3. **Real-time Feedback**: Immediate validation and status updates
4. **Graceful Onboarding**: Smooth transition from identity → account
5. **Trust Through Transparency**: Show security details when users need them
6. **Fail Fast, Fail Clear**: Errors are explicit with actionable guidance

## User Flows

### Flow 1: First-Time User (No Identity)

```
1. Launch App
   ↓
2. Empty State: "Create your first identity"
   ↓
3. Create Identity (existing flow)
   - Choose algorithm (Ed25519 recommended)
   - Set local label
   - Save mnemonic securely
   ↓
4. Prompt: "Register Account?" (optional)
   - Explain benefits: username, multi-device, script publishing
   - Can skip and do later
   ↓
5. [If Register] Account Registration Wizard
   ↓
6. Home screen with identity + account
```

### Flow 2: Existing Identity User (Upgrade to Account)

```
1. Identity List Screen
   ↓
2. Identity Card shows status:
   - ✓ "Account: @username" (if registered)
   - ⚠ "No Account" + "Register" button (if not)
   ↓
3. Tap "Register Account"
   ↓
4. Account Registration Wizard
   ↓
5. Account linked to identity
```

### Flow 3: Account Registration Wizard

```
Step 1: Welcome
- Title: "Create Your Account"
- Subtitle: "Choose a unique username for the ICP network"
- Illustration: Modern graphic

Step 2: Username Selection
- Input field with real-time validation
- Visual feedback:
  ✓ Available (green checkmark)
  ✗ Taken (red X)
  ⚠ Invalid format (orange warning)
- Format rules shown below input
- Reserved usernames highlighted
- Suggestions if taken

Step 3: Review & Confirm
- Show username
- Show public key (truncated with copy button)
- Show IC principal (truncated with copy button)
- Explain: "This will be signed with your identity"
- Big "Create Account" button

Step 4: Processing
- Loading spinner
- Status: "Generating signature..."
- Status: "Submitting to network..."
- Status: "Verifying..."

Step 5: Success
- Celebration animation
- "Account created: @username"
- Show full account details
- Button: "Go to Account Profile"
```

### Flow 4: Add Public Key

```
1. Account Profile Screen
   ↓
2. Tap "Add Key" (floating action button)
   ↓
3. Bottom Sheet: "Add Public Key"
   - Option 1: Use existing identity from device
     - List of local identities without accounts
   - Option 2: Import public key manually
     - Paste hex/base64 key
   ↓
4. Confirm key to add
   - Show public key
   - Show derived IC principal
   ↓
5. Sign operation with current active key
   ↓
6. Success: Key added to account
   - Update UI immediately (optimistic)
   - Refresh from server to confirm
```

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

### 1. Identity List Screen (Enhanced)

**Location**: `lib/screens/identity_home_page.dart` (extend existing)

**Layout**:
```
┌─────────────────────────────┐
│ Identities            [+]   │ ← App bar
├─────────────────────────────┤
│                             │
│ ┌─────────────────────────┐│
│ │ 🔑 alice-key            ││ ← Identity card
│ │ Account: @alice         ││ ← Account status (new)
│ │ aaaaa-aa...             ││ ← Principal
│ │ Ed25519 • Active        ││ ← Algorithm + status
│ └─────────────────────────┘│
│                             │
│ ┌─────────────────────────┐│
│ │ 🔑 bob-key              ││
│ │ ⚠ No Account            ││ ← Warning state
│ │ [Register Account]      ││ ← Action button
│ │ bbbbb-bb...             ││
│ │ secp256k1               ││
│ └─────────────────────────┘│
│                             │
└─────────────────────────────┘
```

**Enhancements**:
- Add `accountStatus` to each identity card
- Show account username or "No Account" state
- "Register Account" button for unregistered identities
- Tap identity → show options: View Profile, Manage Keys, Edit
- Visual badge: "Account" vs "Identity Only"

### 2. Account Registration Wizard

**Location**: `lib/screens/account_registration_wizard.dart` (new)

**Page 1: Username Input**
```
┌─────────────────────────────┐
│ ← Back       1 of 3         │
├─────────────────────────────┤
│                             │
│     Create Your Account     │
│                             │
│   [Illustration: Badge]     │
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
│         [Continue]          │
│                             │
└─────────────────────────────┘
```

**Page 2: Review**
```
┌─────────────────────────────┐
│ ← Back       2 of 3         │
├─────────────────────────────┤
│                             │
│     Review Details          │
│                             │
│ Username                    │
│ @alice                      │
│                             │
│ Public Key                  │
│ 0x1234...abcd    [Copy]    │
│                             │
│ IC Principal                │
│ aaaaa-aa...      [Copy]    │
│                             │
│ This operation will be      │
│ cryptographically signed.   │
│                             │
│     [Create Account]        │
│                             │
└─────────────────────────────┘
```

**Page 3: Processing & Success**
```
┌─────────────────────────────┐
│            3 of 3           │
├─────────────────────────────┤
│                             │
│         🎉                  │
│                             │
│   Account Created!          │
│                             │
│        @alice               │
│                             │
│ Your account is ready on    │
│ the ICP network.            │
│                             │
│  [View Account Profile]     │
│                             │
└─────────────────────────────┘
```

### 3. Account Profile Screen

**Location**: `lib/screens/account_profile_screen.dart` (new)

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

### 4. Add Key Bottom Sheet

**Location**: `lib/widgets/add_account_key_sheet.dart` (new)

**Layout**:
```
┌─────────────────────────────┐
│                          ✕  │
│ Add Public Key              │
├─────────────────────────────┤
│                             │
│ Choose a method:            │
│                             │
│ ┌─────────────────────────┐│
│ │ 🔑 Use Local Identity   ││
│ │ Select from your saved  ││
│ │ identities              ││
│ └─────────────────────────┘│
│                             │
│ ┌─────────────────────────┐│
│ │ 📋 Import Public Key    ││
│ │ Paste a key manually    ││
│ └─────────────────────────┘│
│                             │
└─────────────────────────────┘
```

**Flow A: Use Local Identity**
```
┌─────────────────────────────┐
│ Select Identity             │
├─────────────────────────────┤
│ ○ bob-key                   │
│   bbbbb-bb...               │
│                             │
│ ○ charlie-key               │
│   ccccc-cc...               │
│                             │
│         [Add Key]           │
└─────────────────────────────┘
```

**Flow B: Import Key**
```
┌─────────────────────────────┐
│ Import Public Key           │
├─────────────────────────────┤
│ Public Key (hex/base64)     │
│ ┌─────────────────────────┐│
│ │ 0x1234567890abcdef...   ││
│ │                         ││
│ └─────────────────────────┘│
│                             │
│ Derived Principal:          │
│ ddddd-dd... [Copy]          │
│                             │
│         [Add Key]           │
└─────────────────────────────┘
```

### 5. Key Details Sheet

**Location**: `lib/widgets/account_key_details_sheet.dart` (new)

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
1. Show dialog with steps
2. Update step status in real-time
3. Success: Celebration animation
4. Failure: Error message with retry

**Add/Remove Key**:
1. Optimistic update (immediate UI change)
2. Show subtle spinner
3. On error: Rollback + show snackbar

### Error Handling

**Timestamp Errors** (clock skew):
```
┌─────────────────────────────┐
│ ⏱ Time Sync Issue           │
├─────────────────────────────┤
│ Your device clock may be    │
│ out of sync.                │
│                             │
│ Please check your device    │
│ time settings and try again.│
│                             │
│      [Check Settings]       │
│      [Retry]                │
└─────────────────────────────┘
```

**Signature Errors**:
```
┌─────────────────────────────┐
│ 🔐 Signature Failed          │
├─────────────────────────────┤
│ Could not sign the request. │
│                             │
│ Possible causes:            │
│ • Key has been removed      │
│ • Corrupted key data        │
│                             │
│      [Try Again]            │
│      [Contact Support]      │
└─────────────────────────────┘
```

**Network Errors**:
```
┌─────────────────────────────┐
│ 🌐 Connection Failed         │
├─────────────────────────────┤
│ Could not reach the server. │
│                             │
│ Please check your internet  │
│ connection and try again.   │
│                             │
│      [Retry]                │
│      [Dismiss]              │
└─────────────────────────────┘
```

**Replay Attack (Nonce Reused)**:
```
┌─────────────────────────────┐
│ ⚠ Request Already Processed │
├─────────────────────────────┤
│ This action was already     │
│ submitted. Please refresh   │
│ your account data.          │
│                             │
│      [Refresh]              │
└─────────────────────────────┘
```

## Accessibility

### Screen Reader Support
- Semantic labels for all interactive elements
- Announce status changes (key added/removed)
- Proper focus management in wizards

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
- Success: Confetti or checkmark animation
- Error: Shake animation

### Transitions
- Wizard pages: Slide left/right
- Sheet open/close: Slide up/down
- List items: Fade in with stagger

### Loading
- Circular progress for short operations (<3s)
- Linear progress for multi-step operations
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

1. **Multiple Accounts per Identity**:
   - Current design: 1 identity → 1 account
   - Future: Should one identity be able to create multiple accounts?
   - UX Impact: Need account switcher if yes

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

6. **Offline Mode**:
   - What happens when offline?
   - Can't register accounts or modify keys
   - Need clear offline state indication

7. **Multi-Device Sync**:
   - Identities are stored locally (secure storage)
   - If user adds key from another device, how to import?
   - QR code import flow? Manual key import?

8. **Transaction History**:
   - Backend stores signature_audit
   - Should we show this to users?
   - "Activity Log" showing all account operations

9. **Security Settings**:
   - No timeout/expiry for keys
   - Should there be "require re-auth for sensitive ops"?
   - Biometric confirmation before key operations?

10. **Onboarding Education**:
    - Concepts are complex: identity vs account vs principal vs key
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

- [ ] Registration wizard: All steps flow smoothly
- [ ] Username validation: Real-time feedback works
- [ ] Reserved usernames: Properly rejected
- [ ] Duplicate username: Proper error shown
- [ ] Invalid characters: Proper validation
- [ ] Add key: From local identity works
- [ ] Add key: Manual import works
- [ ] Remove key: Confirmation required
- [ ] Remove last key: Blocked with message
- [ ] Disabled key: Shows in list with proper styling
- [ ] Error states: All error messages clear
- [ ] Loading states: No UI jank
- [ ] Offline mode: Proper indication
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

## Implementation Priority

### Phase 1: Core Functionality (MVP)
1. Account data models
2. API integration
3. Registration wizard (basic)
4. Account profile screen (view only)

### Phase 2: Key Management
5. Add key (local identity only)
6. Remove key
7. Key status visualization

### Phase 3: Polish
8. Real-time username validation
9. Error handling improvements
10. Animations and micro-interactions

### Phase 4: Advanced Features
11. Manual key import
12. Activity log
13. Educational content
14. Accessibility improvements

---

**Status**: Ready for Implementation
**Next Step**: Create account data models and API integration
