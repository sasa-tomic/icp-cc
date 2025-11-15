# ICP Script Marketplace - TODO

## Core Features (Priority: HIGH)

### Cryptographic Signing & Verification
- [ ] Add support in app and backend API for signing and verification with ed25519-dalek
- [ ] Add support in app and backend API for signing and verification with secp256k1

### Script Management
- [ ] Extend UI to support script re-uploading from "My scripts"
- [ ] Extend UI to support script deletion in "Marketplace" tab (with server-side signature verification)
- [ ] Replace random UUID script IDs with user-supplied globally unique slug (or deterministic hash fallback) for stable marketplace links
- [ ] Implement script integrity verification with sha256 checksums

### Script Downloads & Installation
- [ ] Add support for installing a particular version of script locally
- [ ] Implement version management and update notifications
- [ ] Design rollback mechanism for script updates
- [ ] Create installation guides with step-by-step guidance
- [ ] Research if additional assets (images, sounds) should be packaged with scripts

---

## UX Improvements (Priority: HIGH)

### Unified Script Management Interface
- [ ] Create hybrid view combining local and marketplace scripts
- [ ] Add source badges (Local/Marketplace) to distinguish script origins
- [ ] Implement unified search across both local and marketplace scripts
- [ ] Add smart filtering by source, category, tags, and usage frequency
- [ ] Design unified script cards with consistent actions and information

### Script Cards & Display
- [ ] Add complexity indicators (beginner/intermediate/advanced)
- [ ] Display usage statistics (run count, last used, success rate)
- [ ] Create quick action buttons for common tasks (run, edit, share, publish)
- [ ] Add script preview showing key functionality and canister interactions
- [ ] Implement visual indicators for script status (needs update, new version available)

### Publishing Workflow
- [ ] Auto-populate marketplace metadata from local script analysis
- [ ] Design progressive disclosure for advanced publishing options

### Quick Actions Integration
- [ ] "Check for Updates" for downloaded marketplace scripts
- [ ] "Share Script" with marketplace link generation

---

## Lua Scripting & Scripts Tab (Priority: HIGH)

### UI Elements & Features
- [ ] Add tables with columns to UI elements
- [ ] Support paginated lists and loading states driven by Lua
- [ ] Add menu to pick common UI elements/actions in script editor: button, canister method call, message, list
- [ ] Provide input bindings so button actions can incorporate user-entered values
- [ ] Validation and error surfaces for action results in UI container
- [ ] Theming and layout presets for script UIs

### Security & Audit
- [ ] Create security audit logs for script execution

---

## Marketplace Features (Priority: MEDIUM)

### Security & Authentication
- [ ] Implement API key authentication for admin endpoints
- [ ] Add content filtering and moderation system
- [ ] Design content moderation workflow
- [ ] Implement automated content classification

### User Authentication System
- [ ] Implement OAuth provider integration (Google OAuth or similar)
- [ ] Create authentication middleware for API endpoints
- [ ] Add login/logout UI components
- [ ] Implement user profiles and author attribution
- [ ] Add author dashboard for script management
- [ ] Implement JWT or session-based auth
- [ ] Add rate limiting and abuse prevention

### Payment Processing (icpay.org)
- [ ] Research icpay.org API documentation and integration requirements
- [ ] Implement payment gateway client library
- [ ] Add payment UI components and checkout flow
- [ ] Implement purchase tracking and licensing
- [ ] Create database schema for purchases and licenses
- [ ] Add license validation middleware for script access
- [ ] Implement purchase history and receipt generation
- [ ] Add support for paid script tiers
- [ ] Define pricing tiers and feature sets
- [ ] Create UI for tier selection and upgrade prompts

---

## Discovery & Recommendations (Priority: MEDIUM)

### Smart Suggestions
- [ ] Implement smart suggestions based on user behavior and script patterns
- [ ] Create "You might like" section based on local script analysis
- [ ] Show trending scripts in categories user frequently interacts with
- [ ] Implement similar script recommendations based on code analysis
- [ ] Add collaborative filtering from users with similar script patterns
- [ ] Create personalized marketplace homepage per user

### Enhanced Script Creation
- [ ] Mix marketplace templates with built-in templates in creation flow
- [ ] Add "Based on your scripts" suggestions when creating new scripts
- [ ] Add AI-powered suggestions for script improvements and optimizations

### Search Enhancements
- [ ] Implement fuzzy search with typo tolerance
- [ ] Add search suggestions based on user's script patterns
- [ ] Create advanced search filters (complexity, canister type, usage)
- [ ] Add saved searches and search history
- [ ] Implement search result highlighting and relevance scoring

---

## Collaborative Features (Priority: LOW)

### Social & Sharing
- [ ] Create script sharing via shareable links
- [ ] Implement forking functionality for marketplace scripts
- [ ] Add community ratings and reviews integration
- [ ] Create script collections and playlists for organization
- [ ] Add script commenting and discussion features

---

## Testing & Quality Assurance (Priority: HIGH)

### Test Coverage
- [ ] Flutter: widget tests for host loop, event dispatch, effect result handling, and renderer
- [ ] Add integration tests for complete Lua app lifecycle
- [ ] Create performance tests for complex scripts
- [ ] Add accessibility testing for generated UI
- [ ] Cross-browser testing: Flutter app on all target platforms
- [ ] Integration testing: Full end-to-end testing with production data

### HTTP Test Infrastructure Cleanup (Priority: MEDIUM)
**MOTIVATION**: HTTP debugging investigation (2025-10-26) created temporary files that need cleanup.

**Files to Delete:**
- [ ] `apps/autorun_flutter/debug_http_comparison.dart`
- [ ] `apps/autorun_flutter/test_debug_http.dart`
- [ ] `apps/autorun_flutter/test_http_package.dart`

**Files to Review:**
- [ ] Review `upload_fix_verification_test.dart` for remaining debug code
- [ ] Verify `flutter_http_debug_test.dart` still has purpose or can be removed
- [ ] Update test documentation to reflect new UI/API test separation pattern
- [ ] Add reference to root cause document in testing guidelines

---

## Technical Debt & Code Quality (Priority: MEDIUM)

### Code Quality
- [ ] Code review and refactoring of script engine components
- [ ] Performance optimization for large script datasets
- [ ] Memory usage optimization in Flutter renderer
- [ ] Error handling improvements and user feedback enhancement

### Dependencies
- [ ] Update Flutter and Rust dependencies to latest stable versions
- [ ] Review and update SDK versions
- [ ] Security audit of all third-party dependencies

---

## Architecture & Contracts

### Design Principles
- **Untrusted code isolation**: Lua is sandboxed; no IO; effects executed by host
- **Fail fast**: strict schema validation, clear error messages, hard time/step limits
- **Testability**: pure functions (init/view/update) are directly testable

### Lua App Contracts (JSON via FFI)
- `init(arg) -> state, effects[]`
- `view(state) -> ui_v1`
- `update(msg, state) -> state, effects[]`
- Messages: `{ type: string, id?: string, payload?: any }`
- Effects (executed by host): `icp_call`, `icp_batch`
- Host emits results as msgs: `{ type:"effect/result", id, ok, data?|error? }`

### Implementation Status
**Phases 1-4: COMPLETED**
- ✅ Lua app runtime with `init/view/update` functions
- ✅ JSON serialization/deserialization for Lua types
- ✅ Error handling and timeout mechanisms with instruction counting
- ✅ Per-call time/step limits and input/output validation
- ✅ Resource monitoring and limits
- ✅ Complete FFI functions: `icp_lua_app_init/view/update`
- ✅ Dart bridge with `ScriptAppHost` widget
- ✅ UI v1 renderer with all widget types
- ✅ Effects executor for `icp_call`/`icp_batch`
- ✅ Event dispatch system and state management
- ✅ Integration with existing `ScriptsScreen`

**Phase 5: Testing (Ongoing)**

---

## Update Guidelines

### For This Document
- If some task needs to be broken down into smaller actions, add them all as nested subtasks into this TODO.md document
- Whenever some task is completed or found to be already done, REMOVE it from this TODO.md document
- If a whole section is empty, leave a placeholder: `(none)`
- Check if this document is well organized and structured and if not, reorganize and restructure to IMPROVE it.
- Clarify in this document if some task is particularly complex or difficult to do and try to break it down to smaller tasks
- Remember: tasks from **"Update Guidelines"** section should always stay untouched. All other sections in this document MUST be kept up to date.

### Priority Levels
- **High**: Core functionality needed for MVP or critical features
- **Medium**: Important features that improve user experience significantly
- **Low**: Nice-to-have features and minor improvements

---

*Last Updated: 2025-11-14 - Refocused for greenfield development, removed premature production/ops tasks*
