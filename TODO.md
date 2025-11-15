## Fixes and urgent improvements

### 🚨 CRITICAL: Remove API Keys from Flutter App (Security Vulnerability)

**Problem**: Flutter app contains hardcoded Appwrite API keys, exposing credentials to every user who downloads the app.

**Root Cause**: Appwrite Functions require environment variables that aren't being set during deployment, causing 401 errors.

**Files Affected**:
- `apps/autorun_flutter/lib/services/marketplace_open_api_service.dart` (contains API keys)
- `marketplace-deploy/src/functions.rs` (missing environment variable configuration)
- `appwrite/functions/*/src/main.js` (correctly expects environment variables)

**Required Actions**:
1. **HIGH PRIORITY**: Update `marketplace-deploy/src/functions.rs` to set function environment variables:
   - `APPWRITE_FUNCTION_ENDPOINT`
   - `APPWRITE_FUNCTION_PROJECT_ID`
   - `APPWRITE_FUNCTION_API_KEY`
   - `DATABASE_ID`, `SCRIPTS_COLLECTION_ID`, etc.

2. **HIGH PRIORITY**: Remove hardcoded API keys from Flutter app:
   - Remove `_marketplaceApiKey` constant
   - Remove `X-Appwrite-Key` headers
   - Keep functions publicly accessible (`"execute": ["any"]`)

3. **MEDIUM PRIORITY**: Remove unnecessary `appwrite-api-server` - functions should handle this directly

**Testing**: Verify marketplace works without client-side authentication and no keys are exposed in compiled app.

## Update this document (tasks from this section should always stay here)

- If some task needs to be broken down into smaller actions, add them all as nested subtasks into this TODO.md document
- Whenever some task is completed or found to be already done, REMOVE it from this TODO.md document
- If a whole section is empty, leave a placeholder: `(none)`
- Check if this document is well organized and structured and if not, reorganize and restructure to IMPROVE it.
- Clarify in this document if some task is particularly complex or difficult to do and try to break it down to smaller tasks
- Remember: tasks from this section should always stay untouched. All other sections in this document MUST be kept up to date.

## Appwrite deployment

### ✅ COMPLETED: Local Appwrite Docker Compose Setup

**Benefits**: Local development, no production API calls, faster iteration, test isolation

**Implementation Complete**:
- ✅ Deploy latest code to prod Appwrite (pending)
- ✅ Create docker-compose.yml with official appwrite/appwrite image using port 48080
- ✅ Configure API server for local Appwrite endpoint (http://localhost:48080/v1)
- ✅ Update Flutter app with environment switching (local vs production)
- ✅ Add justfile targets for local development workflow
- ✅ Test complete marketplace flow end-to-end locally
- ⏳ Add Rust tests with local Appwrite instance
- ⏳ Document development workflow for future developers

### Bootstrapping a fresh local appwrite instance

Should be fully automated. Seems like appwrite-cli can be used to set up an instance after starting the local docker compose deployment.
```bash
❯ npx appwrite-cli init --help
Usage: appwrite init [options] [command]

The init command provides a convenient wrapper for creating and initializing projects, functions, collections, buckets, teams, and messaging-topics in  Appwrite.

Options:
  -h, --help              display help for command

Commands:
  project [options]       Init a new Appwrite project
  function|functions      Init a new Appwrite function
  site|sites              Init a new Appwrite site
  bucket|buckets          Init a new Appwrite bucket
  team|teams              Init a new Appwrite team
  collection|collections  Init a new Appwrite collection
  table|tables            Init a new Appwrite table
  topic|topics            Init a new Appwrite topic
```

## ICP Autorun Marketplace

### Payment Processing (Priority: High - Next Phase)
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
- Create payment history and receipts
  - Design receipt format and delivery mechanism
  - Add purchase history page for users

### Authentication System (Priority: Medium - After Payment)
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
- Secure API endpoints with authentication middleware
  - Implement JWT or session-based auth
  - Add rate limiting and abuse prevention

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
- Add menu to pick common UI elements/actions in the script editor: button, canister method call, message, list
- Provide input bindings so button actions can incorporate user-entered values
- Validation and error surfaces for action results in the UI container
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
  - Add error boundary and recovery mechanisms
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
- Rust: unit tests for init/view/update JSON roundtrips and timeouts ✅ DONE
- Flutter: widget tests for host loop, event dispatch, effect result handling, and renderer
  - Add integration tests for complete Lua app lifecycle
  - Create performance tests for complex scripts
  - Add accessibility testing for generated UI

