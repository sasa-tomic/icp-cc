import { existsSync } from 'fs'
import { dirname } from 'path'
import type { Plugin } from "@opencode-ai/plugin"

export const ProjectRootPlugin: Plugin = async ({ project, client, $, directory, worktree }) => {
  console.log("Project Root Plugin initialized!")

  const findProjectRoot = (startDir: string): string => {
    let currentDir = startDir
    
    while (currentDir !== '/') {
      const gitDir = `${currentDir}/.git`
      if (existsSync(gitDir)) {
        return currentDir
      }
      
      // Move to parent directory
      currentDir = dirname(currentDir)
    }
    
    // Fallback to original directory if no .git found
    return startDir
  }

  const projectRoot = findProjectRoot(directory)
  
  if (projectRoot !== directory) {
    console.log(`Changing working directory from ${directory} to ${projectRoot}`)
    process.chdir(projectRoot)
  } else {
    console.log(`Already at project root: ${projectRoot}`)
  }

  return {
    // You can add additional hooks here if needed
    event: async ({ event }) => {
      // Handle events if needed
    }
  }
}