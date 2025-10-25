# OpenCode Auto-Exit Plugin

This plugin automatically exits OpenCode when a prompt is provided via the CLI using the `-p` or `--prompt` flag, and detects infinite loops.

## Usage

```bash
opencode -p "your prompt here"
# or
opencode --prompt "your prompt here"
```

## Features

### 1. Auto-Exit on CLI Prompt
The plugin will:
1. Detect that a prompt was provided via CLI
2. Process the prompt normally
3. Automatically exit when the session becomes idle (after prompt completion)

### 2. Infinite Loop Detection
The plugin monitors AI messages and command results to detect infinite loops:
- Tracks the last 10 messages (AI responses + tool results)
- If 5+ consecutive messages are identical, it exits with error code 1
- Normalizes content by trimming whitespace and converting to lowercase
- Logs the repeated messages before exiting

### 3. Unresponsive Agent Detection
- Exits with error if the agent is unresponsive for 30 seconds
- Creates a summary file on completion or error

## Installation

The plugin is automatically loaded from the `.opencode/plugin/` directory in your project.

## How it works

- Checks for `-p` or `--prompt` arguments in `process.argv`
- Listens for `session.start`, `session.idle`, `message.created`, and `tool.completed` events
- Maintains a sliding window of message history for loop detection
- Calls `process.exit(0)` on success, `process.exit(1)` on errors
- Creates `AGENT-RUN-SUMMARY.md` with run status

## Exit Codes

- `0` - Success (prompt completed normally)
- `1` - Error (infinite loop detected or agent unresponsive)

## Files

- `auto-exit.js` - JavaScript implementation
- `auto-exit.ts` - TypeScript implementation with type safety
- `package.json` - Plugin metadata and dependencies
- `README.md` - This documentation