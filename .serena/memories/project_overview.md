# ICP-CC Project Overview

## Project Purpose
ICP Autorun is a Flutter application for running Lua scripts with Internet Computer (ICP) integration. It includes a Rust core for Lua execution and a Poem-based API backend.

## Tech Stack
- **Frontend**: Flutter (Dart)
- **Core Engine**: Rust (mlua crate for Lua execution)
- **Backend**: Poem (Rust web framework with SQLite)
- **Build System**: Just (modern replacement for Make)
- **Language Integration**: FFI between Flutter and Rust

## Project Structure
- `apps/autorun_flutter/`: Main Flutter application
- `crates/icp_core/`: Rust FFI crate for Lua execution engine
- `poem-backend/`: Poem-based API server implementation
- `justfile`: Build configuration and commands
- `scripts/`: Build and platform-specific scripts
- `agent/`: Development tools and utilities

## Key Issues Found
1. **Rust Compilation Errors**: Missing `console_log` macro in `lua_engine.rs`
2. **Type Errors**: Iterator collection issues in performance validation
3. **Test Infrastructure**: Uses Just for comprehensive testing workflow

## Development Commands
- `just test`: Run complete test suite (Rust + Flutter + API server)
- `just rust-tests`: Rust linting, formatting, and tests
- `just flutter-tests`: Flutter analysis and tests
- `just api-up`: Start local API server
- `just api-down`: Stop local API server
- `just clean`: Clean build artifacts

## Testing Requirements
- **Fail Fast**: No silent failures, all infrastructure issues must cause immediate test failures
- **No Fallbacks**: No offline modes or graceful degradation
- **Comprehensive Coverage**: All functions must have unit tests
- **Quality Standards**: Must pass clippy, formatting, and all tests