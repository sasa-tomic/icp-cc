# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Note**: This project uses AGENTS.md files for detailed guidance.

## Primary Reference

@AGENTS.md

## Adaptive Workflow Orchestrator

This project includes an **Adaptive Workflow Orchestrator** system accessible via the `/adaptive` command. The orchestrator provides intelligent, autonomous task management with self-improving capabilities.

### Orchestrator Features
- **Hybrid Execution Modes**: Interactive, autonomous, or hybrid approaches based on task complexity
- **Multi-Agent Parallel Execution**: Deploys specialized agents for different aspects of development
- **Self-Improving Loops**: Iteratively refines solutions based on evaluation feedback
- **Quality Gates**: Automated testing, security review, and performance analysis
- **User Control Points**: Configurable check-ins and progress updates

### Available Specialized Agents
- **Code Generator**: High-quality code implementation with context awareness
- **Fresh Evaluator**: Unbiased quality assessment and issue identification
- **Test Agent**: Comprehensive test coverage for reliability
- **Performance Analyst**: Optimization and bottleneck identification
- **Security Reviewer**: Vulnerability assessment and security best practices

### Configuration
Orchestrator settings are stored in `.claude/orchestrator-config.json`:
- Execution modes and iteration limits
- Agent-specific parameters and timeouts
- Quality thresholds and metrics
- MCP server integrations

### Usage Examples
```bash
/adaptive "Fix the null pointer exception when clicking the Save button"
/adaptive "Implement a new user authentication system with OAuth support" mode:hybrid
/adaptive "Optimize the image processing module for faster runtime" mode:autonomous iterations:infinite
```

## Orchestrator Behavior & Defaults
- **Mode & Interaction**: Default to hybrid mode. The orchestrator should check in with the user at least every 5 iterations or sooner if a major decision arises. Users can explicitly set mode to `interactive`, `autonomous`, or `hybrid` per task.
- **Plan Mode Usage**: For any non-trivial task, begin in Plan Mode (read-only analysis). Only skip Plan Mode for very simple, well-defined tasks.
- **Memory & Logs**: Maintain a log of iterations and outcomes in `./outputs/{task_name}_{timestamp}/` for transparency and post-mortem analysis. Summarize logs when presenting to user to avoid information overload.

## Coding Standards & Quality
- **Language & Style**: Follow the project's coding style (refer to `.stylelintrc` or similar if present). Use idiomatic patterns for the language in use.
- **Testing**: Aim for at least 80% code coverage on new code. Always include critical edge cases in tests.
- **Performance**: If a task has performance requirements, ensure the solution is optimized. No solution should introduce a performance regression; use efficient algorithms and data structures.
- **Security**: All code must handle inputs safely. Follow best practices (e.g., parameterized queries for DB, input validation, avoid insecure functions).
- **Documentation**: Public APIs or complex modules should have clear docstrings or comments. Additionally, major decisions or assumptions should be recorded either in code comments or in the final report to the user.

## Iterative Development Patterns
- **Exploration Phase (Iter 1-3):** Try diverse approaches quickly. It's okay if not all are perfect; the goal is to learn about the problem space.
- **Refinement Phase (Iter 4-7):** Focus on the most promising approach. Fix obvious issues from exploration, tighten the solution to meet requirements.
- **Convergence Phase (Iter 8+):** Polish the solution. Improve performance, clean up code, ensure all tests pass, and edge cases are covered. No new major features should be added here; it's about perfecting what's there.
- These are guidelines; actual iteration counts may vary. The orchestrator should adjust phases based on the situation (e.g., a simple task might converge by iteration 3).

## User Communication
- Always keep the user informed of progress, especially if an iteration might take a long time.
- If the user provides feedback or new info mid-task, incorporate it immediately and adjust the plan (even if mid-iteration).
- If something is truly impossible or conflicts with other requirements, discuss it with the user honestly rather than looping endlessly.

## Failure & Recovery
- If an iteration fails (e.g., code doesn't compile, tests fail badly), log the failure reason and ensure the next iteration addresses it.
- Do not repeat the exact same action expecting a different result; always adjust something (strategy, more context, different agent) when retrying.
- Leverage `learning_context.failed_strategies` to avoid known bad paths. If all known strategies fail, consider reaching out to the user for guidance or re-reading the problem with fresh eyes.

## Context Limit Management
- For large projects, load only relevant portions of the code into context at a time. Use summarization for modules that are too large to read fully, focusing on their interfaces.
- Remove or forget context that is no longer needed as the task progresses, to free up space for new information.

## MCP and Tools
- The orchestrator is expected to use tools (via MCP servers) responsibly. E.g., use the GitHub server to fetch the latest code or commit diff if needed, rather than relying solely on potentially outdated context.
- Clean up any temporary MCP resources after use to avoid side effects (for example, if a scratch database was used for testing, ensure it's properly closed or transactions rolled back).

## Updating AGENTS.md Files

When you discover new information that would be helpful for future development work, please:

- **Update existing AGENTS.md files** when you learn implementation details, debugging insights, or architectural patterns specific to that component
- **Create new AGENTS.md files** in relevant directories when working with areas that don't yet have documentation
- **Add valuable insights** such as common pitfalls, debugging techniques, dependency relationships, or implementation patterns

This helps build a comprehensive knowledge base for the codebase over time
- Immediately after every change run 'just test' to ensure tests are green and add tests to ensure good test coverage.