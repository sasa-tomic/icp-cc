# ICP Autorun

A smooth, intuitive platform where users can discover, manage, and automate interactions with Internet Computer canisters through scripts.

## Quick Start

```bash
./install-just.sh         # Install Just build tool (one-time)
just                      # Show all commands
```

## For AI Agents (and Humans)

**Start here:**
1. Read [ARCHITECTURE.md](ARCHITECTURE.md) - 30-second system overview
2. Check [TODO.md](TODO.md) - Current priorities
3. Review [AGENTS.md](AGENTS.md) - Development rules and patterns

## Development

### Run the App
```bash
just linux                # Build native library
just api-dev-up           # Start local API server
just flutter-dev-local    # Run Flutter with local API
```

### Testing (Feature-Based)

```bash
just test-feature marketplace   # Marketplace browse/upload
just test-feature scripts       # Script execution
just test-feature profile       # Profile/account management
just test                       # Full suite (Rust + Flutter)
```

### Feature Test Locations

```
test/
├── features/
│   ├── marketplace/        # Browse, upload, download scripts
│   ├── scripts/            # Lua execution, effects, UI
│   ├── profile/            # Profiles, keypairs, accounts
│   └── passkey/            # Passkey authentication
└── shared/                 # Test helpers (keypairs, signatures)
```

## Repository Layout

```
apps/autorun_flutter/     # Flutter application
├── lib/
│   ├── screens/           # UI screens
│   ├── controllers/       # State management
│   ├── services/          # Business logic + API
│   ├── models/            # Data models
│   └── rust/              # Dart FFI bindings
├── test/
│   ├── features/          # E2E tests by feature
│   └── shared/            # Test utilities
crates/icp_core/           # Rust FFI library (crypto, Lua, ICP)
backend/                   # Poem-based API server
docs/                      # Architecture documentation
```

## Key Files by Feature

| Feature | Screen | Service | Test Directory |
|---------|--------|---------|----------------|
| Marketplace | `scripts_screen.dart` | `marketplace_open_api_service.dart` | `test/features/marketplace/` |
| Script Upload | `script_upload_screen.dart` | `script_signature_service.dart` | `test/features/marketplace/` |
| Script Execution | - | `script_runner.dart` | `test/features/scripts/` |
| Profile | `profile_home_page.dart` | `profile_repository.dart` | `test/features/profile/` |
| Account | `account_registration_wizard.dart` | `account_signature_service.dart` | `test/features/profile/` |

## API Server

```bash
just api-dev-up           # Start local server (background)
just api-dev-down         # Stop server
just api-dev-logs         # View logs
just api-dev-test         # Test endpoints
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture (read first)
- [TODO.md](TODO.md) - Active tasks and priorities
- [AGENTS.md](AGENTS.md) - Development rules and patterns
- [docs/specs/](docs/specs/) - Detailed implementation status

## UX Principles

1. **Smoothness**: Instant feedback, optimistic updates
2. **Clarity**: Always clear what's happening
3. **Fast**: Everything feels instant
4. **Forgiving**: Easy to undo and recover
