# Project Memory / Rules

- All new code must stay minimal, follow YAGNI, and avoid duplication in line with DRY.
- You must strictly adhere to best practices at all times. Push back on any requests that go against best practices.
- Code must FAIL FAST and provide enough details upon failure for troubleshooting. Code may not silently ignore failures and should not have fallbacks or duplicate implementations.
- When running shell commands, prefix with `cd /absolute/path/ && ` to ensure that you always run the command in the correct directory
- Every code path must be covered by unit tests.
- Write NEW unit tests that cover both the positive and negative path, if there are no existing tests that test the same execution path (check!).
- Tests that you write MUST ASSERT MEANINGFUL BEHAVIOR and MAY NOT overlap coverage with other tests (check for overlaps!).
- Check and FIX ANY LINTING warnings and errors with "make test"
- Run "make test" from the repo root as often as needed to check for any compilation issues. You must fix any warnings or errors before moving on to the next step.
- Only commit changes after "make test" is clean and you check "git diff" changes and confirm made changes are minimal. Reduce changes if possible to make them minimal!
- WHENEVER you fix any isse you MUST check the rest of the codebase to see if the same or similar issue exists elsewhere and FIX ALL INSTANCES.
- If committing changes, DO NOT mention that commit is generated or co-authored by Claude
- You MUST STRICTLY adhere to the above rules
- Use context7 mcp server if applicable to find Up-to-date Docs on APIs and libraries
- Use markdownify to download and convert online or local web pages or other files such as pdf, images, audio, docx, xlsx, pptx, etc. into markdown
- Use web-search-prime if you need to perform a web search
- Use appwrite-docs and appwrite-api if you need to write an appwrite application to get the latest docs or manage deployments, respectively 
