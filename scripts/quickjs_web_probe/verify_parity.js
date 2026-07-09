#!/usr/bin/env node
// R-3 WU-2/WU-3 — parity-suite browser verification harness.
//
// Loads the Flutter-built parity probe
// (`flutter build web --target=lib/web_probe_parity_main.dart`), waits for it
// to publish its combined JSON result to `document.title`, parses it, and
// asserts EVERY golden vector passed (loaded + allPassed).
//
// Run via:  just verify-quickjs-web-parity
// (installs playwright, builds the probe, serves build/web, runs this script
// under a FOREGROUND timeout — never background-launches a browser/Xvfb).
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
    port: Number(process.env.PROBE_PORT) || 8754,
    titleMatcher: '"allPassed"',
  });

  console.log("=== diagnostics ===");
  console.log(JSON.stringify(diagnostics, null, 2));
  if (consoleLines.length) {
    console.log("=== browser console ===");
    console.log(consoleLines.join("\n"));
  }

  console.log("\n=== vector results ===");
  let allOk = true;
  let ok = assert(result.loaded === true, `loaded === true (got ${result.loaded})`);
  allOk = allOk && ok;
  ok = assert(
    result.allPassed === true,
    `allPassed === true (got ${result.allPassed})`
  );
  allOk = allOk && ok;

  let passN = 0;
  let failN = 0;
  for (const c of result.checks || []) {
    if (c.pass) {
      passN++;
      console.log(`    [PASS] ${c.name}`);
    } else {
      failN++;
      allOk = false;
      console.log(`    [FAIL] ${c.name}`);
      console.log(`           ${c.detail || "(no detail)"}`);
    }
  }
  console.log(`\n  ${passN} passed, ${failN} failed (of ${result.checks.length})`);

  if (!allOk) {
    console.error(`\n${failN} vector(s) FAILED`);
    process.exit(1);
  }
  console.log("\nALL PARITY ASSERTIONS PASSED");
})().catch((e) => {
  console.error("HARNESS FATAL:", e);
  process.exit(2);
});
