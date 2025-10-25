import type { Plugin } from "@opencode-ai/plugin"

export const AutoExitPlugin: Plugin = async ({ project, client, $, directory, worktree }) => {
  let hasPrompt = false
  
  // Check if prompt was provided via CLI at startup
  const promptIndex = process.argv.findIndex(arg => arg === '-p' || arg === '--prompt')
  hasPrompt = promptIndex !== -1 && promptIndex + 1 < process.argv.length
  
  return {
    event: async ({ event }) => {
      if (event.type === "session.start" && hasPrompt) {
        console.log("Auto-exit: Prompt provided via CLI, will exit after processing")
      }
      
      // Exit when session becomes idle after processing a prompt
      if (event.type === "session.idle" && hasPrompt) {
        console.log("Auto-exit: Prompt processing complete, exiting...")
        process.exit(0)
      }
    },
  }
}