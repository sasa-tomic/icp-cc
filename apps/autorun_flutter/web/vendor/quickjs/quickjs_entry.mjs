// Vendored entry for quickjs-emscripten (R-3 WU-1).
//
// This file is the SINGLE source bundled into
// `web/vendor/quickjs/quickjs_emscripten.bundle.js` via esbuild:
//   esbuild quickjs_entry.mjs --bundle --format=esm --platform=browser \
//     --minify --banner:js="<license>" \
//     --outfile=apps/autorun_flutter/web/vendor/quickjs/quickjs_emscripten.bundle.js
//
// It wires the `@jitl/quickjs-singlefile-browser-release-sync` variant (WASM
// inlined as base64 — no separate .wasm fetch) into the core engine API and
// exposes a plain global `globalThis.__quickjsEmscripten` that the Dart side
// (`lib/rust/web/quickjs_engine.dart`) reads via `dart:js_interop`.
//
// The WASM module load is KICKED OFF HERE (it returns a Promise) so that by the
// time Dart awaits `__quickjsEmscripten.modulePromise`, instantiation is
// already in flight. `shouldInterruptAfterDeadline` is exposed so Dart can
// build interrupt handlers that mirror `runtime.rs`'s deadline model.
import {
  newQuickJSWASMModuleFromVariant,
  shouldInterruptAfterDeadline,
} from "quickjs-emscripten-core";
import RELEASE_SYNC_BROWSER from "@jitl/quickjs-singlefile-browser-release-sync";

// Start the (async) WASM instantiate immediately; store the promise.
const modulePromise = newQuickJSWASMModuleFromVariant(RELEASE_SYNC_BROWSER);

globalThis.__quickjsEmscripten = {
  // Promise<QuickJSWASMModule> — awaited once by WebQuickJsEngine.bootstrap().
  modulePromise,
  // (deadlineMs: number) => () => boolean — interrupt handler factory.
  shouldInterruptAfterDeadline,
  // Version of the vendored quickjs-emscripten build, for diagnostics.
  version: "0.32.0",
};
