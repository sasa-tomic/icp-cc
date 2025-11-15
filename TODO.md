# ICP Script Marketplace - TODO

## Immediate Tasks (Ready to Start)

- Adjust the UI to align it closely with fantastic UX on mobile devices that typically have narrow screen - much taller than wide.
- Make the script size more compact in the marketplace. We are now consuming a lot of vertical space for each script.
- Extend the UI to support script re-uploading from "My scripts"
- Extend the UI to support script deletion in the "Marketplace" tab (server would do the request signature checking)

### Production Deployment (Priority: HIGH)

## Production Readiness Checklist (Priority: CRITICAL)

### Documentation & Operations
- [ ] **Deployment Guide**: Create step-by-step production deployment guide
- [ ] **Operations Manual**: Document day-to-day operations procedures
- [ ] **User Documentation**: Update user guides for production environment
- [ ] **API Documentation**: Generate and publish comprehensive API docs

## UX Improvements & Marketplace Integration

### Unified Script Management Interface (Priority: High)
- Create hybrid view combining local and marketplace scripts
  - Add source badges (Local/Marketplace) to distinguish script origins
  - Implement unified search across both local and marketplace scripts
  - Add smart filtering by source, category, tags, and usage frequency
  - Design unified script cards with consistent actions and information

### Seamless Publishing Workflow (Priority: High)
- ✅ Add "Publish to Marketplace" directly from local scripts
  - [ ] Auto-populate marketplace metadata from local script analysis
  - [ ] Design progressive disclosure for advanced publishing options

### Improved Discovery and Recommendations (Priority: Medium)
- Implement smart suggestions based on user behavior and script patterns
  - Create "You might like" section based on local script analysis
  - Show trending scripts in categories user frequently interacts with
  - Implement similar script recommendations based on code analysis
  - Add collaborative filtering from users with similar script patterns
  - Create personalized marketplace homepage per user

### Improved Script Creation Flow (Priority: Medium)
- Enhance template system with marketplace integration
  - Mix marketplace templates with built-in templates in creation flow
  - Add "Based on your scripts" suggestions when creating new scripts
  - Add AI-powered suggestions for script improvements and optimizations

### Script Version Management (Priority: Medium)
- Implement version control and update notifications
  - Add update notifications for downloaded marketplace scripts
  - Create version history and rollback options for marketplace scripts
  - Implement auto-update preferences per script with user control
  - Add change logs and release notes for script updates
  - Create seamless update flow that preserves user customizations

### Improved Script Cards and Display (Priority: High)
- Rich script cards with more context and quick actions
  - Add complexity indicators (beginner/intermediate/advanced)
  - Display usage statistics (run count, last used, success rate)
  - Create quick action buttons for common tasks (run, edit, share, publish)
  - Add script preview showing key functionality and canister interactions
  - Implement visual indicators for script status (needs update, new version available)

### Collaborative Features (Priority: Low)
- Add social and collaborative elements to script management
  - Create script sharing via shareable links
  - Implement forking functionality for marketplace scripts
  - Add community ratings and reviews integration
  - Create script collections and playlists for organization
  - Add script commenting and discussion features

### Quick Actions Integration (Priority: High)
- ✅ Add marketplace actions directly to scripts tab
  - ✅ "View in Marketplace" for local scripts with published versions
  - [ ] "Check for Updates" for downloaded marketplace scripts
  - [ ] "Share Script" with marketplace link generation

### Search and Discovery Enhancements (Priority: Medium)
- Improve search functionality across script sources
  - Implement fuzzy search with typo tolerance
  - Add search suggestions based on user's script patterns
  - Create advanced search filters (complexity, canister type, usage)
  - Add saved searches and search history
  - Implement search result highlighting and relevance scoring

### Error Handling and User Feedback (Priority: Medium)
- Improve error handling and user guidance
  - Add contextual error messages with suggested fixes
  - Create guided workflows for common script operations
  - Implement progress indicators for long-running operations
  - Add undo/redo functionality for script management actions
  - Create help tooltips and contextual guidance throughout app

## Marketplace Features

### Security & Compliance
- [ ] **API Authentication**: Implement API key authentication for admin endpoints

### Script Downloads & Installation (Priority: High)
- ✅ Enhance existing script retrieval with file download functionality
  - ✅ Create script preview functionality (code snippets, screenshots, reviews)
  - [ ] Create script installation guides and documentation, with step-by-step guidance
  - [ ] Implement version management and update notifications
  - [ ] Add support for installing locally a particular version of script
  - [ ] Design rollback mechanism for script updates
  - [ ] Analyze and research if other assets such as images and sound would be good to package with scripts
  - [ ] Add verification of script integrity and checksums: sha256 of each script

### Payment Processing Integration (Priority: Medium)
- Integrate with icpay.org for script payments
  - Research icpay.org API documentation and integration requirements
  - Implement payment gateway client library
  - Add payment UI components and checkout flow
  - Implement purchase tracking and licensing
  - Create database schema for purchases and licenses
  - Add license validation middleware for script access
  - Implement purchase history and receipt generation
  - Add support for paid script tiers
  - Define pricing tiers and feature sets
  - Create UI for tier selection and upgrade prompts
  - Design receipt format and delivery mechanism
  - Add purchase history page for users

### User Authentication System (Priority: Medium)
- Add authentication (Google OAuth or similar) required for script uploads
  - Implement OAuth provider integration
  - Create authentication middleware for API endpoints
  - Add login/logout UI components
  - Implement user profiles and author attribution
  - Design user profile schema and UI
  - Add author attribution to script listings
  - Create author dashboard for script management
  - Add user registration and login flows
  - Design onboarding experience
  - Create email verification and password recovery
  - Implement JWT or session-based auth
  - Add rate limiting and abuse prevention
  - Secure API endpoints with authentication middleware

### Security (Priority: Medium - Ongoing)
- Add CSP headers and security best practices
  - Add content filtering and moderation system
  - Design content moderation workflow
  - Implement automated content classification

## Scripts tab and Lua scripting

### Testing & Quality Assurance
- [ ] **Cross-browser Testing**: Test Flutter app on all target platforms
- [ ] **Integration Testing**: Full end-to-end testing with production data

### Design Principles
- **Untrusted code isolation**: Lua is sandboxed; no IO; effects executed by host
- **Fail fast**: strict schema validation, clear error messages, hard time/step limits
- **Testability**: pure functions (init/view/update) are directly testable

### Feature Enhancements (Priority: High)
- Create security audit logs for script execution
- Add tables with columns to UI elements
- Support paginated lists and loading states driven by Lua
- Add menu to pick common UI elements/actions in script editor: button, canister method call, message, list
- Provide input bindings so button actions can incorporate user-entered values
- Validation and error surfaces for action results in UI container
- Theming and layout presets for script UIs

### Security Enhancements (Priority: Medium - Later)
- (none - sandboxing already implemented)

### Architecture and Contracts

**Lua App Contracts (JSON via FFI)**:
- `init(arg) -> state, effects[]`
- `view(state) -> ui_v1`
- `update(msg, state) -> state, effects[]`
- Messages: `{ type: string, id?: string, payload?: any }`
- Effects (executed by host): `icp_call`, `icp_batch` (more later)
- Host emits results as msgs: `{ type:"effect/result", id, ok, data?|error? }`

### Implementation Plan (Complex - Breakdown Required)

**Phase 1-4: COMPLETED**
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
- Flutter: widget tests for host loop, event dispatch, effect result handling, and renderer
  - Add integration tests for complete Lua app lifecycle
  - Create performance tests for complex scripts
  - Add accessibility testing for generated UI

### Testing & Quality Assurance (Ongoing)
#### Comprehensive Testing Strategy

- Flutter: widget tests for host loop, event dispatch, effect result handling, and renderer
  - Add integration tests for complete Lua app lifecycle
  - Create performance tests for complex scripts
  - Add accessibility testing for generated UI

#### HTTP Test Infrastructure Cleanup (Priority: MEDIUM)
**MOTIVATION**: HTTP debugging investigation (2025-10-26) created several temporary files and modifications that need cleanup.

**Files Created During Investigation (CAN BE DELETED):**
- `apps/autorun_flutter/debug_http_comparison.dart` - Debug script for HTTP comparison
- `apps/autorun_flutter/test_debug_http.dart` - Fixed HttpTestHelper API usage  
- `apps/autorun_flutter/test_http_package.dart` - Fixed HttpTestHelper API usage

**Files Modified During Investigation (REVIEW NEEDED):**
- `apps/autorun_flutter/test/integration/upload_fix_verification_test.dart` - Split into UI-only test
- `apps/autorun_flutter/test/integration/upload_fix_api_test.dart` - NEW: API-only test (KEEP)
- `apps/autorun_flutter/test/flutter_http_debug_test.dart` - URL consistency fixes (127.0.0.1 → localhost)

**Cleanup Tasks:**
- [ ] Delete temporary debug files: `debug_http_comparison.dart`, `test_debug_http.dart`, `test_http_package.dart`
- [ ] Review `upload_fix_verification_test.dart` for any remaining debug code that can be cleaned up
- [ ] Verify `flutter_http_debug_test.dart` still has purpose or can be removed
- [ ] Update test documentation to reflect new UI/API test separation pattern

**Root Cause Documentation:**
- [ ] Add reference to root cause document in testing guidelines section below

#### Development Infrastructure
- ⏳ Add Rust tests with local Cloudflare Workers instance
- ⏳ Document development workflow for future developers
- ⏳ Implement CI/CD pipeline with security scanning
- ⏳ **HTTP Testing Guidelines**: Document TestWidgetsFlutterBinding vs real HTTP testing patterns (see `HTTP_TEST_DEBUGGING_ROOT_CAUSE.md`)

---

## Documentation Updates

### Development Guides
- ⏳ Document Lua App architecture and contract system
- ⏳ Create security best practices guide for script development
- ⏳ Update deployment documentation for new function architecture

### API Documentation
- ⏳ Generate comprehensive API documentation for marketplace endpoints
- ⏳ Document Lua App helper functions and UI components
- ⏳ Create integration examples and tutorials

---

## Technical Debt & Maintenance

### Code Quality (Ongoing)
- [ ] Code review and refactoring of script engine components
- [ ] Performance optimization for large script datasets
- [ ] Memory usage optimization in Flutter renderer
- [ ] Error handling improvements and user feedback enhancement

### Dependencies (Periodic)
- [ ] Update Flutter and Rust dependencies to latest stable versions
- [ ] Review and update SDK versions
- [ ] Security audit of all third-party dependencies

---

## Infrastructure & Operations

### Backup & Disaster Recovery
- [ ] **Backup Testing**: Regularly test backup restoration procedures
- [ ] **Rollback Plan**: Document rollback procedures for deployments

### Monitoring & Observability (Priority: Medium)
- [ ] Implement comprehensive logging for function execution
- [ ] Add performance monitoring and alerting
- [ ] Create health check endpoints for marketplace services
- [ ] Set up automated backup and recovery procedures

### Monitoring & Observability
- [ ] **Error Tracking**: Set up error monitoring (Sentry, Cloudflare analytics)
- [ ] **Performance Monitoring**: Configure APM and performance metrics
- [ ] **Logging**: Set up structured logging for production debugging
- [ ] **Health Checks**: Implement comprehensive health check endpoints
- [ ] **Alerting**: Set up alerts for downtime, errors, performance issues

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
- **High**: Core functionality needed for MVP or critical security issues
- **Medium**: Important features that improve user experience significantly
- **Low**: Nice-to-have features and minor improvements

---

*Last Updated: 2025-10-26 - Added HTTP test infrastructure cleanup tasks and root cause documentation*
