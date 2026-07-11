#!/usr/bin/env node
// R-3 WU-4 — production-path browser verification harness.
//
// Loads the Flutter-built production-path probe
// (`flutter build web --target=tool/web_probe_app_main.dart`), which runs the
// shipped 01_hello_world.js through the REAL production stack
// (probeQuickJsReadiness -> RustScriptBridge -> ScriptAppRuntime) and asserts
// the full init->view->update lifecycle works on Web.
//
// Run via:  just verify-quickjs-web-app
const { runProbe } = require("./probe_runner");

function assert(cond, msg) {
  if (cond) console.log("  PASS:", msg);
  else {
    console.log("  FAIL:", msg);
    return false;
  }
  return true;
}

(async () => {
  const { result, diagnostics, consoleLines } = await runProbe({
    port: Number(process.env.PROBE_PORT) || 8755,
    titleMatcher: '"allPassed"',
  });

  console.log("=== diagnostics ===");
  console.log(JSON.stringify(diagnostics, null, 2));
  if (consoleLines.length) {
    console.log("=== browser console ===");
    console.log(consoleLines.join("\n"));
  }

  console.log("\n=== production-path checks ===");
  let allOk = assert(
    result.allPassed === true,
    `allPassed === true (got ${result.allPassed})`
  );
  for (const c of result.checks || []) {
    const ok = assert(c.pass === true, `${c.name}: ${c.detail}`);
    allOk = allOk && ok;
  }

  if (!allOk) {
    console.error("\nPRODUCTION-PATH probe FAILED");
    process.exit(1);
  }
  console.log("\nPRODUCTION-PATH PROBE PASSED — a real script runs init/view/update on Web");
})().catch((e) => {
  console.error("HARNESS FATAL:", e);
  process.exit(2);
});
