# OpenCode Auto-Exit Plugin

This plugin automatically exits OpenCode when a prompt is provided via the CLI using the `-p` or `--prompt` flag.

## Usage

```bash
opencode -p "your prompt here"
# or
opencode --prompt "your prompt here"
```

The plugin will:
1. Detect that a prompt was provided via CLI
2. Process the prompt normally
3. Automatically exit when the session becomes idle (after prompt completion)

## Installation

The plugin is automatically loaded from the `.opencode/plugin/` directory in your project.

## How it works

- Checks for `-p` or `--prompt` arguments in `process.argv`
- Listens for `session.start` and `session.idle` events
- Calls `process.exit(0)` when the session becomes idle after processing a CLI prompt

## Files

- `auto-exit.js` - JavaScript implementation
- `auto-exit.ts` - TypeScript implementation with type safety
- `package.json` - Plugin metadata and dependencies