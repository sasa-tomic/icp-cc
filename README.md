# ICP Autorun

A smooth, intuitive platform where users can discover, manage, and automate interactions with Internet Computer canisters through scripts.

## Quick Start

```bash
./scripts/bootstrap.sh    # Install dependencies (one-time)
./install-just.sh         # Install Just build tool (one-time)
just                      # Show all commands
```

## Development

### Run the App
```bash
# Linux
just linux && cd apps/autorun_flutter && flutter run -d linux

# With local API server
just api-dev-up
just flutter-dev-local

# Android
just android && cd apps/autorun_flutter && flutter run -d <device-id>
```

### API Server
```bash
just api-dev-up           # Start local server (background)
just api-dev-down         # Stop server
just api-dev-logs         # View logs
just api-dev-test         # Test endpoints
just api-dev-reset        # Reset database
```

### Testing
```bash
just test                 # Run all tests (Rust + Flutter)
just rust-tests           # Rust tests + clippy
just flutter-tests        # Flutter tests
```

### Build Platforms
```bash
just linux                # Linux desktop
just android              # Android (all ABIs)
just macos                # macOS
just ios                  # iOS
just windows              # Windows
just all                  # All platforms
```

### Docker Deployment
```bash
just docker-dev-up        # Start dev containers
just docker-prod-up       # Start prod with Cloudflare Tunnel
just docker-all-status    # Check all containers
```

## Repository Layout

```
apps/autorun_flutter/     # Flutter application
crates/icp_core/          # Rust FFI library
backend/                  # Poem-based API server
scripts/                  # Build helpers
docs/                     # Architecture docs
```

## Documentation

- [TODO.md](TODO.md) - Active tasks
- [PASSKEY_IMPLEMENTATION_PLAN.md](PASSKEY_IMPLEMENTATION_PLAN.md) - Security architecture
- [docs/ACCOUNT_PROFILES_DESIGN.md](docs/ACCOUNT_PROFILES_DESIGN.md) - Account system

## UX Principles

1. **Smoothness**: Instant feedback, optimistic updates
2. **Clarity**: Always clear what's happening
3. **Fast**: Everything feels instant
4. **Forgiving**: Easy to undo and recover
