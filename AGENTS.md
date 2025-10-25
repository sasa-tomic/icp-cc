# Project Memory / Rules

- All new code must stay minimal, follow YAGNI, and avoid duplication in line with DRY.
- You must strictly adhere to best practices at all times. Push back on any requests that go against best practices.
- Code must FAIL FAST and provide enough details upon failure for troubleshooting. Code may not silently ignore failures and should not have fallbacks or duplicate implementations.
- When running shell commands, prefix with `cd /absolute/path/ && ` to ensure that you always run the command in the correct directory
- Every code path must be covered by unit tests.
- WRITE NEW UNIT TESTS that cover both the positive and negative path of the new functionality.
- Tests that you write MUST ASSERT MEANINGFUL BEHAVIOR and MAY NOT overlap coverage with other tests (check for overlaps!).
- Check and FIX ANY LINTING warnings and errors with "just test-machine"
- Run "just test-machine" from the repo root as often as needed to check for any compilation issues. You must fix any warnings or errors before moving on to the next step.
- Only commit changes after "just test-machine" is clean and you check "git diff" changes and confirm made changes are minimal. Reduce changes if possible to make them minimal!
- WHENEVER you fix any isse you MUST check the rest of the codebase to see if the same or similar issue exists elsewhere and FIX ALL INSTANCES.
- If committing changes, DO NOT mention that commit is generated or co-authored by Claude
- You MUST STRICTLY adhere to the above rules

# MCP servers that you should use in the project
- Use context7 mcp server if your task requires working with a library or API
- Use markdownify to download and convert online or local web pages or other files such as pdf, images, audio, docx, xlsx, pptx, etc. into markdown
- Use web-search-prime if you ever notice that you don't have the correct information on how to use specific library or software
- Use appwrite-docs and appwrite-api if your task is to write or update an appwrite application to get the latest docs or manage deployments, respectively

- **Local Development with Appwrite**: See [LOCAL_DEVELOPMENT.md](./LOCAL_DEVELOPMENT.md) for complete setup guide
- **Appwrite Architecture**: See [docs/appwrite-sites-vs-functions.md](./docs/appwrite-sites-vs-functions.md) for Sites vs Functions decision
- **API Endpoints**: See [docs/appwrite-function-urls.md](./docs/appwrite-function-urls.md) for API endpoint URLs and integration guide
- **IMPORTANT**: We use Appwrite Sites with API routes instead of Functions. See [docs/appwrite-sites-vs-functions.md](./docs/appwrite-sites-vs-functions.md) for detailed reasoning.
