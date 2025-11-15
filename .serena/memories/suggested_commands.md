# Essential Commands for ICP-CC Development

## Primary Development Workflow
```bash
just                    # Show all available commands
just test               # Run complete test suite (REQUIRED after changes)
just clean              # Clean all build artifacts
just all                # Build all platforms
```

## Platform-Specific Builds
```bash
just linux              # Build for Linux desktop
just android            # Build for Android
just macos              # Build for macOS
just ios                # Build for iOS
just windows            # Build for Windows
```

## Cloudflare Workers Development
```bash
just cloudflare-dev                 # Start local development server
just cloudflare-deploy              # Deploy to production
just cloudflare-test-up             # Start test environment
just cloudflare-test-down           # Stop test environment
just cloudflare-types               # Generate TypeScript types
```

## Individual Test Commands
```bash
just _rust-tests         # Rust linting, formatting, and tests
just _flutter-tests      # Flutter analysis and tests
just test-with-cloudflare # Flutter tests with Cloudflare Workers
```

## Flutter Development
```bash
just flutter-local       # Run Flutter app with local Cloudflare Workers
just flutter-production # Run Flutter app with production environment
```

## Quality Standards
```bash
cargo clippy             # Rust linting (must pass)
cargo fmt                # Rust formatting (must pass)
cargo nextest run        # Rust tests (must pass)
flutter analyze          # Flutter analysis (must pass)
flutter test             # Flutter tests (must pass)
```

## Critical Requirements
- **NEVER** commit changes without running `just test` first
- **ALL** tests must pass - no skipping, no fallbacks
- **NO** silent failures - infrastructure issues must cause immediate test failure
- **FIX** all linting warnings and errors before proceeding