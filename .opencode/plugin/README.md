# Project Root Plugin

This OpenCode plugin automatically finds the project root by looking for the nearest `.git` directory and sets the current working directory to that location.

## Features

- **Automatic project root detection**: Searches up the directory tree for `.git`
- **Fallback to current directory**: If no `.git` is found, stays in the current directory
- **Minimal and efficient**: Uses Node.js built-in modules only

## Usage

Simply place this plugin in your `.opencode/plugin` directory. OpenCode will automatically load it when starting a session.

The plugin will:
1. Find the nearest `.git` directory starting from the current working directory
2. Change to that directory if it's different from the current one
3. Log the action taken

## Files

- `project-root.js` - JavaScript version
- `project-root.ts` - TypeScript version with type safety

Use either version based on your preference.