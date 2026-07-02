/// Web stub for [setProcessEnvImpl]. The browser has no libc process
/// environment; this is never reached on Web (the readiness probe bypasses
/// auto-start via `kIsWeb`). Honest no-op returning `false`.
library;

bool setProcessEnvImpl(String name, String value) => false;
