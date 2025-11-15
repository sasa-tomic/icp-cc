# ICP Autorun - Product Requirements & Vision

**Last Updated**: 2025-11-14
**Status**: Greenfield app requiring UX overhaul and feature alignment

---

## Product Vision

A smooth, intuitive platform where users can discover, manage, and automate interactions with Internet Computer canisters through scripts. The app should feel awesome and professional, making complex operations simple.

---

## Core User Flows

### 1. Script Development & Management

**Current State**: Users have local scripts and marketplace scripts in separate tabs, disconnected experience.

**Target Experience**:
- Users write scripts **locally** (future: AI-assisted generation via API endpoints)
- Seamless transition from local development → testing → publishing
- Clear visibility of script status (local draft, published, updates available)
- One unified view showing both local and marketplace scripts with clear visual distinction
- Easy script editing with auto-save and version history

**Requirements**:
- [ ] Plan for AI generation API endpoints (design endpoints but don't implement yet)
- [ ] Unified script management view (no tabs, single integrated list)
- [ ] Smooth upload/publish flow with minimal friction
- [ ] Auto-metadata extraction where possible
- [ ] Version comparison UI for updates
- [ ] Local script editing with syntax highlighting improvements

---

### 2. Discovery & Marketplace

**Current State**: Basic search exists, but discovery is limited. Trending/recommendations are TODO stubs.

**Target Experience**:
- Users find popular canisters based on **real marketplace stats** (downloads, ratings, usage)
- Personalized recommendations ("You might like", "Trending in your categories")
- Rich script cards showing complexity, usage examples, compatibility
- Clear trust indicators (verification badges, author reputation)
- Easy filtering by use case, canister, category

**Requirements**:
- [ ] Implement trending algorithm based on recent downloads + ratings
- [ ] Add personalized recommendations (based on user's downloads/bookmarks)
- [ ] Enhance script cards with:
  - Complexity indicator (beginner/intermediate/advanced)
  - Usage stats (installs, active users)
  - Compatibility badges (Rust canister, JS canister, etc.)
  - Preview of what the script does (first few lines or description)
- [ ] Trust system:
  - Verified author badges
  - Security audit status
  - Community reputation score
- [ ] Better search UX with instant results, filters as chips

---

### 3. Canister Interaction

**Current State**: Users can interact with canisters via queries/updates, with or without identity.

**Target Experience**:
- Intuitive canister explorer with autocomplete for canister IDs
- Smart argument input (JSON validation, type hints)
- Response formatting (pretty JSON, tables for structured data)
- History of recent interactions
- Ability to save favorite canisters

**Requirements**:
- [ ] Canister autocomplete/search in the app
- [ ] Smart input forms based on Candid interface (parse .did files)
- [ ] Response viewer with multiple formats (JSON, Table, Raw)
- [ ] Interaction history with replay capability
- [ ] Favorite canisters list
- [ ] Error messages that are user-friendly (no raw exceptions)

---

### 4. Script Automation

**Current State**: Scripts can be executed, but scheduling/automation unclear.

**Target Experience**:
- Users automate queries and update calls using scripts
- Schedule scripts to run periodically
- Set triggers (e.g., "run every hour", "run when balance changes")
- View automation logs and results history
- Pause/resume automations easily

**Requirements**:
- [ ] Script scheduler UI (cron-like but user-friendly)
- [ ] Trigger system (time-based, event-based future work)
- [ ] Automation logs with filtering and search
- [ ] Quick enable/disable toggle for automations
- [ ] Notifications for automation failures

---

### 5. User Profile & Data Management

**Current State**: Profiles exist with display name, contact details. No encryption for stored credentials.

**Target Experience**:
- Users have a profile stored in DB with name, contact, social links
- All profile operations are **secure** (requests signed with Ed25519 or better)
- Users can edit profile smoothly with instant validation feedback
- Contact details stored securely
- Profile privacy controls (public/private fields)

**Requirements**:
- [ ] Secure profile updates with signature verification
- [ ] Real-time validation (unique username, valid URLs, etc.)
- [ ] Profile privacy settings (what's public vs private)
- [ ] Social proof display (GitHub, Twitter, etc.)
- [ ] Profile completeness indicator (encourage users to fill out info)

---

### 6. Security & Authentication

**Current State**: Ed25519 signatures for some operations, but gaps exist (profile updates unprotected).

**Target Requirements**:

#### 6.1 Request Authentication
- **All DB operations** must be signed with Ed25519 (or propose better alternative)
- Signature verification on backend for every state-changing operation
- Consider alternatives if easier:
  - **Passkey/WebAuthn** (modern, built into browsers/OS)
  - **ECDSA secp256k1** (already supported, could standardize)
  - **Hybrid approach**: Passkey for web, Ed25519 for native

**Decision Needed**:
- Current: Ed25519 + secp256k1 both supported, but inconsistently applied
- Recommendation: Standardize on **Passkeys** for primary auth (better UX), keep Ed25519 for script signing

#### 6.2 Credential Storage
**Current State**: Keys stored in platform secure storage, but server-side credential storage not encrypted.

**Target**:
- Users can store credentials **on server** encrypted with:
  - **Option 1**: Strong password (PBKDF2/Argon2 derived key)
  - **Option 2**: Passkey (WebAuthn credential for encryption)
  - **Option 3**: Hardware security key (YubiKey, etc.)

**Requirements**:
- [ ] Client-side encryption before sending to server (server never sees plaintext)
- [ ] Key derivation from user password/passkey (use Argon2id)
- [ ] Encrypted blob storage in DB with associated metadata
- [ ] Secure key rotation mechanism
- [ ] Recovery flow (security questions, backup codes, or similar)

**Proposed Architecture**:
```
User Password/Passkey → Argon2id KDF → Encryption Key
                                     ↓
                     Encrypt(User Credentials) → Store in DB
                                     ↓
                     Server stores encrypted blob only
```

#### 6.3 API Security
- [ ] All endpoints require authentication (except public search/browse)
- [ ] Rate limiting per user (prevent abuse)
- [ ] Request signing with replay attack prevention (timestamp + nonce)
- [ ] HTTPS only (enforce in production)
- [ ] CORS properly configured

---

### 7. Script Installation & Updates

**Current State**: Scripts can be downloaded, but update notifications and version management unclear.

**Target Experience**:
- Users "install an app" (== download + enable script)
- Client checks server for latest version of each installed script
- Users get **notifications** when updates are available
- Users can choose to:
  - Auto-update (recommended for trusted scripts)
  - Review changes before updating
  - Stay on current version
  - Install specific older version if needed (rollback)

**Requirements**:
- [ ] "Installed Apps" view showing all downloaded scripts
- [ ] Update checker that runs periodically (configurable interval)
- [ ] Update notification system (in-app badges, optional push)
- [ ] Changelog viewer (compare versions)
- [ ] Version pinning (user locks to specific version)
- [ ] Rollback capability (downgrade to previous version)
- [ ] Update queue (batch updates or one-by-one)

**Implementation Notes**:
- Backend already has `version` field in scripts table
- Need to add:
  - `installed_scripts` table linking user → script → version
  - `check_updates` endpoint returning list of newer versions
  - Frontend service to periodically poll for updates
  - UI components for update notifications and management

---

### 8. Payment Support (Future)

**Current State**: Everything is free.

**Future Plan**:
- Premium scripts (paid one-time or subscription)
- Tipping mechanism for free scripts
- Revenue sharing for authors
- Payment methods: ICP tokens, cycles, credit card (Stripe?)

**Requirements (Not Immediate)**:
- [ ] Design payment API endpoints (don't implement yet)
- [ ] Plan database schema for transactions, subscriptions
- [ ] Consider escrow/smart contract for trustless payments
- [ ] Tax/compliance considerations (consult legal)

**Preparation Now**:
- [ ] Add `price` and `payment_required` fields to scripts (already exists)
- [ ] Add `payment_status` to user downloads
- [ ] Design pricing tiers (free, one-time, subscription)

---

## Technical Architecture Alignment

### Current Issues to Fix
1. **Monolithic backend**: 2,795 lines in single `main.rs` (refactor into modules)
2. **UUID IDs**: Should use human-readable slugs for scripts (`icp-ledger-balance` not `550e8400-...`)
3. **Inconsistent auth**: Some endpoints signed, others not (standardize)
4. **No rate limiting**: Vulnerable to abuse
5. **Limited error handling**: Some endpoints return generic errors
6. **No caching**: Marketplace queries hit DB every time
7. **No pagination**: Search returns all results (will break with scale)

### Proposed Improvements
- [ ] Refactor backend into modules: `auth`, `marketplace`, `scripts`, `profiles`, `db`
- [ ] Add slug generation for scripts (unique, human-readable)
- [ ] Implement request signing for all state-changing endpoints
- [ ] Add Redis/in-memory cache for popular queries
- [ ] Implement pagination (limit=20, cursor-based)
- [ ] Add proper error types with user-friendly messages
- [ ] Add telemetry/logging for debugging

---

## UX Principles

1. **Smoothness**: No jarring transitions, instant feedback, optimistic updates
2. **Clarity**: Always clear what's happening, what's clickable, what state you're in
3. **Trust**: Security features visible but not intrusive (badges, padlocks, etc.)
4. **Forgiving**: Easy to undo, rollback, recover from mistakes
5. **Fast**: Everything feels instant (use caching, prefetching, optimistic UI)
6. **Professional**: Polished design, consistent spacing, proper typography
7. **Helpful**: Tooltips, examples, inline help where needed

---

## Success Metrics

- **Onboarding**: New user to first script execution < 2 minutes
- **Publishing**: Local script to marketplace < 1 minute
- **Discovery**: User finds relevant script within 30 seconds
- **Updates**: Users notified within 1 hour of new version release
- **Security**: Zero plaintext credentials stored server-side
- **Performance**: All API calls < 200ms (p95)
- **Reliability**: 99.9% uptime, zero data loss

---

## Open Questions & Decisions Needed

1. **Auth Method**: Stick with Ed25519 or switch to Passkeys? (Recommendation: Passkeys for users, Ed25519 for scripts)
2. **Encryption**: Argon2id + AES-256-GCM for server-side credential storage? (Alternative suggestions welcome)
3. **Slug Format**: `author/script-name` or just `script-name`? (Recommend: `author/script-name` for namespacing)
4. **Update Frequency**: How often should client check for updates? (Recommend: daily + manual refresh)
5. **Versioning**: Semantic versioning (1.2.3) or simple integers? (Recommend: semver)
6. **Payments**: ICP tokens only or multi-currency? (Future decision)

---

## Implementation Phases

### Phase 1: Security & Foundation (Week 1-2)
- Fix authentication gaps (all endpoints signed)
- Implement encrypted credential storage
- Add rate limiting and CORS
- Refactor backend into modules

### Phase 2: UX Overhaul (Week 3-4)
- Unified script view (no tabs)
- Smooth upload/download flows
- Profile editing improvements
- Better error messages

### Phase 3: Discovery & Updates (Week 5-6)
- Trending/recommendations
- Update notification system
- Version management UI
- Changelog viewer

### Phase 4: Polish & Scale (Week 7-8)
- Performance optimization (caching, pagination)
- Rich script cards with stats
- Automation scheduler UI
- Canister explorer improvements

---

## Notes

- This is a **living document** - update as requirements evolve
- See `CODEBASE_OVERVIEW.md` for current implementation details
- All changes must follow TDD, YAGNI, DRY principles per `AGENTS.md`
- Security is **non-negotiable** - no shortcuts

---

## Does This Make Sense?

Review the above and confirm:
1. Are the user flows aligned with your vision?
2. Is the proposed auth/encryption approach acceptable? (Passkeys vs Ed25519)
3. Are the phases reasonable?
4. Any critical features missing?
5. Ready to start implementation?
