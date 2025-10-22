# Project Memory / Rules

- All new code must stay minimal, follow YAGNI, and avoid duplication in line with DRY.
- Code must FAIL FAST and report enough details upon failure, for troubleshooting. Code may not silently ignore failures.
- Every code path must be covered by unit tests.
- Tests must assert meaningful behavior and avoid overlapping coverage.
- Check for ANY linting errors with "make test"
- Run "make test" from the repo root as often as needed to check for any compilation issues. You must fix any warnings or errors before moving on to the next step.
- Only commit changes after "make test" is clean and you check "git" changes and confirm changes are minimal
- You MUST STRICTLY adhere to the above rules
- Use context7 mcp server if applicable to find Up-to-date Docs on APIs and libraries
- Use zai-mcp-server for vision tasks
- Use web-search-prime if you need to perform a web search
- Use appwrite-docs and appwrite-api if you need to write an appwrite application to get the latest docs or manage deployments, respectively 
