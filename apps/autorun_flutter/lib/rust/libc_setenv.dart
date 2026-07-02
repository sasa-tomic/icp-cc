/// Sets a process environment variable on the current (native) process.
///
/// Conditional-import split (R-1). On Linux this calls libc `setenv` via FFI so
/// libsecret (running in-process) picks up the new value — used to export
/// `DBUS_SESSION_BUS_ADDRESS` for the gnome-keyring auto-start (WU-S2). Returns
/// `true` on success.
///
/// Returns `false` on every non-Linux IO platform (nothing to do) and on Web
/// (there is no libc process environment in the browser; this path is never
/// reached on Web because the readiness probe bypasses auto-start there).
library;

import 'libc_setenv_io.dart' if (dart.library.html) 'libc_setenv_web.dart';

bool setProcessEnv(String name, String value) =>
    setProcessEnvImpl(name, value);
