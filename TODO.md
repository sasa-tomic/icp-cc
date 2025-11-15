# ICP Script Marketplace - TODO

## Immediate Tasks (Ready to Start)

- Adjust the UI to align it closely with fantastic UX on mobile devices that typically have narrow screen - much taller than wide.
- Make the script size more compact in the marketplace. We are now consuming a lot of vertical space for each script.
- When uploading a script, mandatory sign it with the identity (private key) of the script author. When listing the script show the identity of the author as an ICP principal (first 5 characters should be enough for now).
- In requests to update or delete the script, sign the request in a reliable way with the private key (identity) of the script author and at the server side compare that the request signer matches the script author. Allow script updates or deletions if the signatures of author + requestor match.
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
  - [ ] "Check for Updates" for downloaded marketplace scripts
  - [ ] "View in Marketplace" for local scripts with published versions
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
  - [ ] Create script installation guides and documentation, with step-by-step guidance
  - [ ] Implement version management and update notifications
  - [ ] Add support for installing locally a particular version of script
  - [ ] Design rollback mechanism for script updates
  - [ ] Create script preview functionality (code snippets, screenshots, reviews)
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

#### Rust Lua Engine Test Coverage (Priority: HIGH)
- **MOTIVATION**: Recent bug showed `icp_searchable_list` function missing from Rust engine, causing runtime errors. Only 1/13 helper functions had test coverage.
- ✅ Add tests for remaining action helpers: `icp_call`, `icp_batch`, `icp_message`, `icp_ui_list`, `icp_result_display`, `icp_section`, `icp_table`
- ✅ Add tests for formatting helpers: `icp_format_number`, `icp_format_icp`, `icp_format_timestamp`, `icp_format_bytes`, `icp_truncate`
- ✅ Add tests for data manipulation helpers: `icp_filter_items`, `icp_sort_items`
- ✅ Create regression test to verify all 13 helper functions are available in both Rust and Flutter environments

### 🚨 **CRITICAL GAPS IDENTIFIED**

**Missing Helper Function in Rust Engine:**
- Flutter has `icp_group_by` function (line 641 in script_runner.dart) but Rust engine is missing this function
- This could cause same runtime error if any script uses `icp_group_by`

**Function Signature Mismatches:**
- `icp_message`: Flutter uses `icp_message(text)` but Rust uses `icp_message(spec)` - **FIXED**
- `icp_section`: Flutter uses `icp_section(title, content)` but Rust uses `icp_section(spec)` - **FIXED**  
- `icp_table`: Flutter returns `type: "result_display"` but Rust returns `type: "table"` - **FIXED**

**Immediate Action Required:**
- ✅ Add `icp_group_by` function to Rust engine to prevent runtime errors
- ✅ Add test for `icp_group_by` function
- ✅ Update regression test to check for 16 functions instead of 15

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
- ✅ Documented in `HTTP_TEST_DEBUGGING_ROOT_CAUSE.md`
- [ ] Add reference to root cause document in testing guidelines section below

#### Development Infrastructure
- ⏳ Add Rust tests with local Cloudflare Workers instance
- ⏳ Document development workflow for future developers
- ⏳ Implement CI/CD pipeline with security scanning
- ⏳ **HTTP Testing Guidelines**: Document TestWidgetsFlutterBinding vs real HTTP testing patterns (see `HTTP_TEST_DEBUGGING_ROOT_CAUSE.md`)

#### Database & Testing Infrastructure
- ✅ **IMPORTANT**: Current E2E tests use REAL Cloudflare D1 database (not mocks)
  - Local D1 instance: `.wrangler/state/v3/d1/miniflare-D1DatabaseObject/*.sqlite`
  - Database initialized with proper schema via `wrangler d1 execute icp-marketplace-db --local --file=migrations/0001_initial_schema.sql`
  - Test data includes 1 real script for comprehensive API testing
  - All 20 integration tests validate actual API endpoints and database operations
- **TODO**: Add test data seeding for more comprehensive testing scenarios
- **TODO**: Add separate test database configuration for isolated testing
- **TODO**: Implement database cleanup/reset between test runs
- **HIGH PRIORITY**: Automate CF infrastructure setup/teardown for test runs
  - **Setup Phase**: Automatically spin up local Cloudflare Workers and D1 database before tests
    - Start local Wrangler dev server programmatically
    - Initialize fresh D1 database with schema migrations
    - Seed test data for comprehensive testing scenarios
    - Wait for server to be healthy before proceeding
    - Handle port conflicts and environment cleanup
  - **Teardown Phase**: Automatically clean up infrastructure after tests complete
    - Stop Wrangler dev server gracefully
    - Clean up temporary database files
    - Reset environment state
    - Ensure no lingering processes or ports
  - **Implementation**: Add to `test/integration/comprehensive_e2e_test.dart` in `setUpAll`/`tearDownAll`
  - **Alternative**: Create separate test runner script that manages full lifecycle
  - **Benefits**: Isolated test environment, no manual setup, CI/CD compatibility

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
- [ ] **Database Backups**: Configure automated D1 database backups
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
