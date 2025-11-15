# Project Memory / Rules

- All new code must stay minimal, follow YAGNI, and avoid duplication in line with DRY.
- Code must FAIL FAST and report enough details upon failure, for troubleshooting. Code may not silently ignore failures.
- Every code path must be covered by unit tests.
- Tests must assert meaningful behavior and avoid overlapping coverage.
- All tests and code must compile without warnings
- All tests must pass
- For rust code ensure the following passes without any warnings or errors, ensuring good test coverage after fixing any potential errors or warnings:
❯ cargo clippy --benches --tests --all-features && cargo clippy && cargo fmt --all && cargo nextest run
- For flutter code ensure linter and `flutter test` and `flutter analyze` are completely clean without warnings or errors - fix if anything is not clean
- Only commit changes after all the above is satisfied
