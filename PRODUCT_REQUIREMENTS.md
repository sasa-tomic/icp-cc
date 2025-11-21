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

**Current State**: Users can interact with canisters via queries/updates, with or without keypair.

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

#### 6.1 Request Authentication & Encryption Architecture

**DECISION (2025-11-14)**: Hybrid Approach - Passkey Authentication + Password-Based Vault Encryption

After research, we're implementing **Option 1** from the security analysis:
- **Authentication**: Passkeys via WebAuthn (phishing-resistant, great UX for login)
- **Vault Encryption**: Separate password for encrypting stored credentials (zero-knowledge)
- **Recovery**: Password recovery codes (rock-solid, well-understood)

**Why This Works**:
- ✅ Best of both worlds: Passkey UX for frequent logins, password for encryption
- ✅ Separation of concerns: Authentication ≠ encryption (losing passkey ≠ losing data)
- ✅ Platform-independent: Works on all devices (no Windows 11 PRF fragmentation)
- ✅ Easy implementation: Mature libraries (`webauthn-rs` + `passkeys` package)
- ✅ Rock-solid recovery: Password recovery codes proven solution

**Implementation Stack**:
- **Backend (Rust)**: `webauthn-rs` v0.5.2 + `argon2` crate
- **Frontend (Flutter)**: `passkeys` package v2.16.0 + Argon2id via FFI/pointycastle
- **Parameters**: Argon2id (time=3, mem=64MB, parallelism=4) for Bitwarden-level security

#### 6.2 Authentication Requirements
- [ ] Integrate `webauthn-rs` for passkey registration/authentication
- [ ] Create `/api/passkey/register` and `/api/passkey/authenticate` endpoints
- [ ] Store passkey credentials in database (linked to user accounts)
- [ ] Support multiple passkeys per user (force ≥2 for redundancy)
- [ ] Alert users on new passkey registration
- [ ] Log authentication attempts with device metadata

#### 6.3 Vault Encryption Requirements
- [ ] Client-side encryption with Argon2id-derived key from vault password
- [ ] Enforce strong password (min 16 chars, complexity requirements)
- [ ] Encrypt credentials with AES-256-GCM before sending to server
- [ ] Server stores encrypted blob + salt per user (zero-knowledge)
- [ ] Never transmit or store vault password server-side
- [ ] Decrypt credentials in memory only, never persist decrypted

#### 6.4 Recovery Mechanism Requirements
- [ ] Generate 12 recovery codes (base32-encoded) during setup
- [ ] Hash recovery codes with bcrypt/Argon2id before storage
- [ ] Allow one-time use for vault password reset
- [ ] Provide download/print functionality for recovery codes
- [ ] Multiple confirmation warnings about irrecoverability
- [ ] Audit trail for recovery code usage

**Architecture**:
```
┌─────────────────────────────────────────────────────────┐
│ Authentication (Frequent)                               │
│ User → Passkey (WebAuthn) → Backend → Session Token    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Vault Access (Occasional)                               │
│ Vault Password → Argon2id → Encryption Key             │
│                             ↓                           │
│              Decrypt(Credentials) ← Server Blob         │
│                             ↓                           │
│              Use in memory, never persist               │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Recovery (Emergency)                                    │
│ Recovery Code → Verify Hash → Allow Password Reset     │
└─────────────────────────────────────────────────────────┘
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

**REVISED 2025-11-14**: Prioritizing UX improvements first for immediate "awesome" feel, then security hardening.

### Phase 1: UX Overhaul (Week 1-2) **← CURRENT FOCUS**
- Unified script view (no tabs, single integrated experience)
- Smooth upload/download flows with visual feedback
- Script slug generation (author/script-name instead of UUIDs)
- Profile editing improvements with real-time validation
- Better error messages (user-friendly, actionable)
- Fix navigation bugs and disconnected views
- Responsive design improvements

### Phase 2: Security & Foundation (Week 3-6)
- **See `PASSKEY_IMPLEMENTATION_PLAN.md` for complete details**
- Implement passkey authentication (WebAuthn)
- Implement vault encryption (Argon2id + AES-GCM)
- Recovery code system
- Add rate limiting and CORS
- Fix authentication gaps (signature verification on all endpoints)
- Database schema already prepared (3 new tables created)

### Phase 3: Discovery & Updates (Week 7-8)
- Trending/recommendations based on marketplace stats
- Update notification system
- Version management UI
- Changelog viewer
- Rich script cards with complexity/usage indicators

### Phase 4: Polish & Scale (Week 9-10)
- Performance optimization (caching, pagination)
- Refactor backend from monolithic main.rs into modules
- Automation scheduler UI
- Canister explorer improvements
- Production hardening

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
