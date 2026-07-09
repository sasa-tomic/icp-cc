#!/usr/bin/env node
// R-3 WU-1 browser verification harness.
//
// Loads the Flutter-built web app (probe entrypoint:
// `flutter build web --target=lib/web_probe_main.dart`), waits for the probe
// to publish its JSON result to `document.title`, parses it, and asserts.
//
// Run via:  just verify-quickjs-web
// (which installs playwright, builds the probe, serves build/web, then runs
// this script under a FOREGROUND timeout — never background-launches a
// browser/Xvfb in your shell).
//
// Why a separate harness (not `flutter test --platform chrome`): Flutter 3.38
// has no chrome test platform, and the QuickJS engine is browser-only
// (`dart:js_interop` can't even be imported in the VM — see plan §2.3). This
// harness is the headless-Chrome test path R-3 introduces; it is reused by
// every parity WU (WU-2..WU-5).
const { chromium } = require("playwright");
const http = require("http");
const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const BUILD_DIR = path.join(
  REPO_ROOT,
  "apps/autorun_flutter/build/web"
);
const PORT = Number(process.env.PROBE_PORT) || 8753;
const URL = `http://127.0.0.1:${PORT}/`;

function staticHandler(req, res) {
  let p = decodeURIComponent(req.url.split("?")[0]);
  if (p === "/") p = "/index.html";
  const fp = path.join(BUILD_DIR, p);
  if (
    !fp.startsWith(BUILD_DIR) ||
    !fs.existsSync(fp) ||
    fs.statSync(fp).isDirectory()
  ) {
    res.writeHead(404);
    res.end("not found: " + p);
    return;
  }
  const ext = path.extname(fp).toLowerCase();
  const types = {
    ".html": "text/html",
    ".js": "text/javascript",
    ".mjs": "text/javascript",
    ".json": "application/json",
    ".wasm": "application/wasm",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".map": "application/json",
  };
  res.writeHead(200, { "content-type": types[ext] || "application/octet-stream" });
  fs.createReadStream(fp).pipe(res);
}

(async () => {
  if (!fs.existsSync(path.join(BUILD_DIR, "index.html"))) {
    console.error(
      `FAIL: ${BUILD_DIR}/index.html not found. Run \`flutter build web --target=lib/web_probe_main.dart\` first.`
    );
    process.exit(2);
  }

  const server = http.createServer(staticHandler);
  await new Promise((r) => server.listen(PORT, "127.0.0.1", r));
  console.log("serving", BUILD_DIR, "at", URL);

  let browser, page;
  const failures = [];
  try {
    browser = await chromium.launch({ headless: true });
    page = await browser.newPage();
    // The app pulls in the `passkeys` plugin (unrelated to R-3). Its web init
    // throws + calls window.close() when the Corbado PasskeyAuthenticator SDK
    // isn't loaded. Stub it so the probe page survives (the probe entrypoint
    // is Flutter-free, but the engine bootstrap still touches the plugin).
    await page.addInitScript(() => {
      window.PasskeyAuthenticator = window.PasskeyAuthenticator || {
        init: () => {},
        discover: () => Promise.resolve({}),
      };
    });
    const consoleLines = [];
    page.on("console", (m) => consoleLines.push(`[${m.type()}] ${m.text()}`));
    page.on("pageerror", (e) =>
      consoleLines.push(`[pageerror] ${e.stack || e.message}`)
    );

    await page.goto(URL, { waitUntil: "domcontentloaded", timeout: 30000 });

    // Poll document.title until it looks like the probe JSON, or timeout.
    let title = "";
    const deadline = Date.now() + 40000;
    while (Date.now() < deadline) {
      title = await page.title();
      if (title.startsWith("{") && title.includes('"loaded"')) break;
      await page.waitForTimeout(250);
    }

    const diag = await page.evaluate(() => ({
      qjsGlobal: typeof window.__quickjsEmscripten,
      qjsVersion: window.__quickjsEmscripten && window.__quickjsEmscripten.version,
      probeDiv: !!document.getElementById("probe-result"),
    }));
    console.log("=== diagnostics ===");
    console.log(JSON.stringify(diag, null, 2));
    console.log("=== document.title ===");
    console.log(title);
    if (consoleLines.length) {
      console.log("=== browser console ===");
      console.log(consoleLines.join("\n"));
    }

    let result;
    try {
      result = JSON.parse(title);
    } catch (e) {
      console.error("FAIL: document.title is not probe JSON:", title.slice(0, 200));
      process.exit(1);
    }

    function assert(cond, msg) {
      if (cond) console.log("  PASS:", msg);
      else {
        console.log("  FAIL:", msg);
        failures.push(msg);
      }
    }

    console.log("\n=== assertions ===");
    assert(result.loaded === true, `loaded === true (got ${result.loaded})`);
    assert(result.version === "0.32.0", `version === 0.32.0 (got ${result.version})`);
    assert(result.evalResult === 3, `evalCode('1+2') === 3 (got ${result.evalResult})`);
    assert(result.argRoundtrip === 84, `arg.n*2 === 84 (got ${result.argRoundtrip})`);
    assert(
      result.memoryLimitHalted === true,
      `memoryLimitHalted === true (got ${result.memoryLimitHalted}, err=${result.memoryLimitError})`
    );
    assert(
      /out of memory/i.test(result.memoryLimitError || ""),
      `memoryLimitError contains 'out of memory' (got ${result.memoryLimitError})`
    );
    assert(
      result.interruptHalted === true,
      `interruptHalted === true (got ${result.interruptHalted}, err=${result.interruptError})`
    );
    assert(
      /interrupt/i.test(result.interruptError || ""),
      `interruptError contains 'interrupted' (got ${result.interruptError})`
    );
    assert(
      result.interruptElapsedMs >= 0 && result.interruptElapsedMs < 5000,
      `interruptElapsedMs < 5000 (got ${result.interruptElapsedMs}ms)`
    );
    assert(
      result.dartClosureInterruptFired === true,
      `dartClosureInterruptFired === true (got ${result.dartClosureInterruptFired})`
    );
    assert(result.error == null, `no top-level error (got ${result.error})`);

    if (failures.length) {
      console.error(`\n${failures.length} assertion(s) FAILED`);
      process.exit(1);
    }
    console.log("\nALL ASSERTIONS PASSED");
  } finally {
    if (browser) await browser.close().catch(() => {});
    server.close();
  }
})().catch((e) => {
  console.error("HARNESS FATAL:", e);
  process.exit(2);
});
