# Adaptive Workflow Orchestrator

A next-generation agentic workflow system for Claude Code that enables intelligent, autonomous task management with self-improving capabilities.

## Quick Start

```bash
# Basic usage
/adaptive "Fix the authentication bug in the login module"

# With specific mode
/adaptive "Implement user OAuth integration" mode:hybrid

# For optimization tasks
/adaptive "Optimize database queries for performance" mode:autonomous iterations:infinite
```

## System Components

### 1. Main Orchestrator (`.claude/commands/adaptive.md`)
- **Hybrid Execution Modes**: Interactive, autonomous, or hybrid approaches
- **Self-Improving Loops**: Iterative refinement based on evaluation feedback
- **Quality Gates**: Automated testing, security, and performance checks
- **User Control Points**: Configurable check-ins and progress updates

### 2. Specialized Agents (`.claude/commands/agents/`)
- **Code Generator**: High-quality implementation with context awareness
- **Fresh Evaluator**: Unbiased quality assessment and issue identification
- **Test Agent**: Comprehensive test coverage for reliability
- **Performance Analyst**: Optimization and bottleneck identification
- **Security Reviewer**: Vulnerability assessment and security best practices

### 3. Configuration (`.claude/orchestrator-config.json`)
- Execution modes and iteration limits
- Agent-specific parameters and timeouts
- Quality thresholds and metrics
- MCP server integrations

### 4. Learning System (`.claude/orchestrator-learning/`)
- Persistent knowledge storage across sessions
- Strategy effectiveness tracking
- Pattern library for reusable solutions
- Performance analytics

## Workflow Phases

1. **Planning & Context Assembly**: Read-only analysis and plan creation
2. **Parallel Agent Deployment**: Specialized agents work on subtasks
3. **Synthesis & Evaluation**: Integration and unbiased quality assessment
4. **Iterative Improvement**: Self-refinement based on feedback
5. **Convergence & Delivery**: Final polish and delivery

## Configuration Options

```json
{
  "orchestratorConfig": {
    "defaultMode": "hybrid",
    "maxIterations": 20,
    "parallelAgentLimit": 5,
    "qualityThreshold": 85,
    "autoPauseOnStagnation": true
  }
}
```

## Key Features

- **Intelligent Mode Selection**: Automatically chooses optimal execution approach
- **Quality Assurance**: Multi-layer review process with specialized agents
- **Adaptive Learning**: Improves performance over time
- **User Control**: Configurable interaction points and progress updates
- **Stagnation Detection**: Automatically pauses when progress stalls
- **Comprehensive Logging**: Full transparency and audit trails

## Best Practices

1. **Start Simple**: Use basic `/adaptive "task description"` for straightforward tasks
2. **Specify Mode**: Use `mode:hybrid` for complex features requiring user input
3. **Set Iterations**: Use `iterations:infinite` for optimization tasks
4. **Review Plans**: Always review the initial plan before execution
5. **Monitor Progress**: Check in during iteration breaks for course correction

## Integration with Existing Tools

- **MCP Servers**: Automatically connects to GitHub, filesystem, and database servers
- **Testing Frameworks**: Integrates with existing test infrastructure
- **CI/CD Pipelines**: Compatible with continuous integration workflows
- **Code Review**: Complements human code review processes

## Troubleshooting

- **Stalled Progress**: Orchestrator automatically pauses and asks for guidance
- **Quality Issues**: Iterative refinement continues until thresholds met
- **Context Limits**: Smart context management prevents overflow
- **Agent Timeouts**: Configurable timeouts prevent runaway processes

## File Structure

```
.claude/
├── commands/
│   ├── adaptive.md              # Main orchestrator command
│   └── agents/                  # Specialized agents
│       ├── code_generator.md
│       ├── fresh_evaluator.md
│       ├── test_agent.md
│       ├── performance_analyst.md
│       └── security_reviewer.md
├── orchestrator-config.json     # Configuration settings
├── orchestrator-learning/       # Learning storage
├── logs/                        # Execution logs
└── README.md                    # This file
```

## Advanced Usage

The orchestrator can handle complex, multi-step tasks like:

- **Feature Development**: From requirements to deployed feature
- **System Refactoring**: Large-scale code improvements
- **Performance Optimization**: End-to-end performance analysis
- **Security Audits**: Comprehensive security assessments
- **Architecture Design**: System design and implementation

Each task is automatically broken down into manageable subtasks, assigned to appropriate agents, and iteratively improved until quality standards are met.