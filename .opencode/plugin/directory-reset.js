export const DirectoryResetPlugin = async ({ project, client, $, directory, worktree }) => {
  // Cache the repo root at agent start
  let repoRoot = null;
  
  // Initialize at plugin load time
  try {
    repoRoot = await $`git rev-parse --show-toplevel`.text();
    repoRoot = repoRoot.trim();
  } catch (error) {
    repoRoot = await $`pwd`.text();
    repoRoot = repoRoot.trim();
  }

  return {
    // Before any tool execution, reset to repo root and inform AI
    "tool.execute.before": async (input, output) => {
      try {
        // Change to repo root and persist for the command
        input.command = `cd "${repoRoot}" && ${input.command}`;
        
        // Inform AI of current directory
        await client.session.prompt({
          path: { id: project.sessionId },
          body: {
            parts: [{ type: "text", text: `CWD: "${repoRoot}"` }]
          }
        });
      } catch (error) {
        console.warn(`Directory reset plugin error: ${error.message}`);
      }
    },
  }
}
