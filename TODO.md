# ICP Script Marketplace - TODO

## Immediate Tasks (Ready to Start)

### Production Deployment (Priority: HIGH)
- [ ] Set up Cloudflare account and authenticate with wrangler
- [ ] Create production D1 database and run migrations
- [ ] Configure production environment variables and secrets
- [ ] Deploy Cloudflare Workers to production
- [ ] Update Flutter app with production API endpoint
- [ ] Test production deployment end-to-end
- [ ] Set up custom domain and SSL certificates
- [ ] Configure monitoring and error tracking
- [ ] Set up backup and disaster recovery procedures

### Environment Setup & Configuration
- [x] Run `just test-machine` to ensure all tests are passing
- [x] Update git status and commit any remaining changes



### Quick Wins

- [ ] Create basic script download API endpoint structure
- [ ] Add input validation to existing API endpoints
- [x] Clean up all remaining references to the failed Appwrite experiment throughout the codebase

## Production Readiness Checklist (Priority: CRITICAL)

### Infrastructure & Deployment
- [ ] **Cloudflare Account Setup**: Create Cloudflare account, authenticate wrangler CLI
- [ ] **Production Database**: Create production D1 database with proper migrations
- [ ] **Environment Configuration**: Set production environment variables and secrets
- [ ] **Worker Deployment**: Deploy Cloudflare Workers to production environment
- [ ] **Domain Configuration**: Set up custom domain (icp-marketplace.com or similar)
- [ ] **SSL/TLS**: Configure SSL certificates and HTTPS
- [ ] **CDN Setup**: Configure Cloudflare CDN for static assets

### Security & Compliance
- [ ] **Input Validation**: Add comprehensive input validation to all API endpoints
- [ ] **Rate Limiting**: Implement rate limiting to prevent abuse
- [ ] **CORS Configuration**: Set proper CORS headers for production domain
- [ ] **Security Headers**: Add security headers (CSP, HSTS, etc.)
- [ ] **API Authentication**: Implement API key authentication for admin endpoints
- [ ] **Data Privacy**: Ensure GDPR/CCPA compliance for user data

### Monitoring & Observability
- [ ] **Error Tracking**: Set up error monitoring (Sentry, Cloudflare analytics)
- [ ] **Performance Monitoring**: Configure APM and performance metrics
- [ ] **Logging**: Set up structured logging for production debugging
- [ ] **Health Checks**: Implement comprehensive health check endpoints
- [ ] **Alerting**: Set up alerts for downtime, errors, performance issues

### Backup & Disaster Recovery
- [ ] **Database Backups**: Configure automated D1 database backups
- [ ] **Backup Testing**: Regularly test backup restoration procedures
- [ ] **Incident Response**: Create incident response runbooks
- [ ] **Rollback Plan**: Document rollback procedures for deployments

### Testing & Quality Assurance
- [ ] **Load Testing**: Perform load testing for expected traffic
- [ ] **Security Testing**: Conduct security audit and penetration testing
- [ ] **Cross-browser Testing**: Test Flutter app on all target platforms
- [ ] **Integration Testing**: Full end-to-end testing with production data

### Documentation & Operations
- [ ] **Deployment Guide**: Create step-by-step production deployment guide
- [ ] **Operations Manual**: Document day-to-day operations procedures
- [ ] **User Documentation**: Update user guides for production environment
- [ ] **API Documentation**: Generate and publish comprehensive API docs

## Active Development Tasks



## Marketplace Features

### Script Downloads & Installation (Priority: High)
- Create script download functionality
  - Build script download API endpoint
  - Add download tracking and analytics: store stats in the DB
  - Create script installation guides and documentation, with step-by-step guidance
  - Design one-click download and installation flow
  - Implement version management and update notifications
  - Add support for installing locally a particular version of the script
  - Design rollback mechanism for script updates
  - Create script preview functionality (code snippets, screenshots, reviews)
  - Analyze and research if other assets such as images and sound would be good to package with scripts
  - Maybe add verification of script integrity and checksums: sha256 of each script
  - Add download history and library management for users

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
- Implement comprehensive input validation for API endpoints
  - Add request/response schema validation
  - Implement SQL injection and XSS prevention
  - Add Lua code syntax validation and security scanning
  - Integrate Lua linter and security analyzer
  - Create sandboxed execution environment
  - Sanitize user-generated content to prevent XSS attacks
  - Implement content sanitization middleware
  - Add CSP headers and security best practices
  - Add content filtering and moderation system
  - Design content moderation workflow
  - Implement automated content classification

## Scripts tab and Lua scripting

### Design Principles
- **Untrusted code isolation**: Lua is sandboxed; no IO; effects executed by host
- **Fail fast**: strict schema validation, clear error messages, hard time/step limits
- **Testability**: pure functions (init/view/update) are directly testable

### Feature Enhancements (Priority: High)
- E2E integration tests covering read→transform→display and read→transform→call
- Create security audit logs for script execution
- Add richer UI elements: tables with columns
- Support paginated lists and loading states driven by Lua
- Add menu to pick common UI elements/actions in script editor: button, canister method call, message, list
- Provide input bindings so button actions can incorporate user-entered values
- Validation and error surfaces for action results in UI container
- Theming and layout presets for script UIs

### Security Enhancements (Priority: Medium - Later)
- Implement script sandboxing and security scanning
- Security: sandbox Lua (whitelist helpers only)

### Architecture and Contracts

**Lua App Contracts (JSON via FFI)**:
- `init(arg) -> state, effects[]`
- `view(state) -> ui_v1`
- `update(msg, state) -> state, effects[]`
- Messages: `{ type: string, id?: string, payload?: any }`
- Effects (executed by host): `icp_call`, `icp_batch` (more later)
- Host emits results as msgs: `{ type:"effect/result", id, ok, data?|error? }`

### Implementation Plan (Complex - Breakdown Required)

**Phase 1: Rust Core (High Priority)**
- Add Lua app runtime that loads script once, locates `init/view/update`, and calls them with JSON bridges
  - Research and integrate mlua or similar Lua runtime
  - Implement JSON serialization/deserialization for Lua types
  - Create error handling and timeout mechanisms
  - Add per-call time/step limits and input/output validation
  - Implement resource monitoring and limits
  - Add input schema validation using serde
  - Serialize/deserialize `state`, `msg`, `ui`, `effects` using serde/json
  - New FFI functions:
  - `icp_lua_app_init(json_arg) -> { ok, state, effects, error? }`
  - `icp_lua_app_view(state) -> { ok, ui, error? }`
  - `icp_lua_app_update(msg, state) -> { ok, state, effects, error? }`

**Phase 2: Dart Bridge (High Priority)**
- Extend `RustBridgeLoader` and `ScriptBridge` to expose `luaAppInit/View/Update`
  - Update FFI bindings to include new Lua app functions
  - Create Dart wrapper classes for Lua app state management
  - Add error handling and type safety

**Phase 3: Flutter Host + Renderer (High Priority)**
- New `ScriptAppHost` widget manages state, runs init/view/update, renders UI, dispatches msgs
  - Implement state management for Lua app lifecycle
  - Create event dispatch system for message passing
  - Implement UI v1 renderer (column, row, text, button, list)
  - Extend existing UI renderer to support new widget types
  - Add interactive element support
  - Implement effects executor for `icp_call`/`icp_batch`; dispatch result msgs to update
  - Create effect execution queue and batch processing
  - Handle async operations and result routing
  - Validate schemas and fail fast with surfaced errors
  - Add comprehensive error reporting
  - Implement user-friendly error display

**Phase 4: Integration (Medium Priority)**
- Update `ScriptsScreen` to launch `ScriptAppHost` instead of one-shot dialog
  - Refactor existing script execution flow
  - Maintain backward compatibility
  - Provide migration shim for old `return icp_ui_list(...)` (optional)

**Phase 5: Testing (Ongoing)**
- Flutter: widget tests for host loop, event dispatch, effect result handling, and renderer
  - Add integration tests for complete Lua app lifecycle
  - Create performance tests for complex scripts
  - Add accessibility testing for generated UI

### Testing & Quality Assurance (Ongoing)
#### Comprehensive Testing Strategy
- ✅ **COMPLETED**: Flutter E2E integration tests with real Cloudflare D1 database (20 tests covering all API endpoints)
- ✅ **COMPLETED**: Real Cloudflare D1 local instance setup with proper schema and test data
- ✅ **COMPLETED**: All integration tests passing with zero tolerance for errors
- Flutter: widget tests for host loop, event dispatch, effect result handling, and renderer
  - Add integration tests for complete Lua app lifecycle
  - Create performance tests for complex scripts
  - Add accessibility testing for generated UI

#### Development Infrastructure
- ✅ **COMPLETED**: Real Cloudflare D1 database integration (no mocks used in tests)
- ✅ **COMPLETED**: Local D1 database with proper schema initialization via migrations
- ✅ **COMPLETED**: All Flutter integration tests with real Cloudflare Workers endpoints
- ⏳ Add Rust tests with local Cloudflare Workers instance
- ⏳ Document development workflow for future developers
- ⏳ Implement CI/CD pipeline with security scanning

#### Database & Testing Infrastructure
- **IMPORTANT**: Current E2E tests use REAL Cloudflare D1 database (not mocks)
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

### Monitoring & Observability (Priority: Medium)
- [ ] Implement comprehensive logging for function execution
- [ ] Add performance monitoring and alerting
- [ ] Create health check endpoints for marketplace services
- [ ] Set up automated backup and recovery procedures

### Deployment Status
- **Previous**: Legacy deployment at https://icp-autorun.appwrite.network (deprecated)
- **Current**: ✅ Migration to Cloudflare Workers COMPLETED with D1 database
- **Local Development**: ✅ Running on http://localhost:8787 with all endpoints functional
- **Infrastructure**: Automated deployment tool (server-deploy) handles complete infrastructure + worker deployment
- **Production**: 🚀 READY FOR DEPLOYMENT - See Production Readiness Checklist above
- [x] Implement `server-deploy bootstrap` command for fresh environment setup
- [ ] Deploy to production Cloudflare Workers environment
- [ ] Implement blue-green deployment strategy for zero downtime
- [ ] Add rollback procedures for failed deployments
- [ ] Set up staging environment for testing production features

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

*Last Updated: 2025-10-25 - Production Readiness Checklist Added*
