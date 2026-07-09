#!/usr/bin/env node
// R-3b WU-0 — browser verification harness for the agent-js IC-agent PoC.
//
// Loads the Flutter-built probe
// (`flutter build web --target=lib/web_probe_agent_main.dart
//   --dart-define=IC_AGENT_PROXY_HOST=http://127.0.0.1:<api-port>`), waits for
// it to publish its JSON result to `document.title`, parses it, and asserts
// ONE real anonymous canister query round-tripped:
//   browser → backend CORS proxy (/api/v1/ic) → IC boundary node (ic0.app) →
//   candid `text` reply ("ICP") decoded in the browser.
//
// Run via:  just verify-ic-agent-web
// (starts `just api-dev-up` for the proxy, installs playwright, builds the
// probe, serves build/web, runs this script under a FOREGROUND timeout).
//
// This is the headless-Chrome test path for R-3b (mirrors R-3a's
// `verify-quickjs-web*`). It drives REAL headless Chromium against the REAL
// proxy + REAL IC boundary node — no mocked network.
const { chromium } = require("playwright");
const http = require("http");
const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const BUILD_DIR = path.join(REPO_ROOT, "apps/autorun_flutter/build/web");
const PORT = Number(process.env.PROBE_PORT) || 8756;
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
      `FAIL: ${BUILD_DIR}/index.html not found. Run \`flutter build web --target=lib/web_probe_agent_main.dart\` first.`
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
    // The app pulls in the `passkeys` plugin (unrelated to R-3b). Its web init
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
    // Observe the agent's proxied fetches (rewritten to /api/v1/ic/...) so a
    // failure is diagnosable from the harness output.
    page.on("request", (req) => {
      if (req.url().includes("/api/v1/ic/")) {
        consoleLines.push(`[proxy-fetch] ${req.method()} ${req.url()}`);
      }
    });

    await page.goto(URL, { waitUntil: "domcontentloaded", timeout: 30000 });

    // Poll document.title until it looks like the probe JSON, or timeout. The
    // real IC query (through verifyQuerySignatures) can take several seconds,
    // so allow a generous window.
    let title = "";
    const deadline = Date.now() + 60000;
    while (Date.now() < deadline) {
      title = await page.title();
      if (title.startsWith("{") && title.includes('"queryOk"')) break;
      await page.waitForTimeout(250);
    }

    const diag = await page.evaluate(() => ({
      agentGlobal: typeof window.__icpCcAgent,
      agentVersion: window.__icpCcAgent && window.__icpCcAgent.version,
      probeDiv: !!document.getElementById("agent-result"),
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
      console.error("FAIL: document.title is not probe JSON:", title.slice(0, 240));
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
    assert(
      result.version === "3.4.3",
      `version === 3.4.3 (got ${result.version})`
    );
    // R-3b WU-2 — fetchCandid through the proxy returns the real ledger .did.
    assert(
      result.candidFetched === true,
      `candidFetched === true (got ${result.candidFetched})`
    );
    // R-3b WU-2 — parseCandid (pure-Dart port) of the REAL ledger .did locates
    // the `symbol` method — parity with native on live metadata, not just the
    // synthetic VM golden vectors.
    assert(
      result.candidParsed === true,
      `candidParsed === true (got ${result.candidParsed})`
    );
    // R-3b WU-2 — the parsed `symbol` return type matches the native
    // `parse_candid_interface` output for the live ledger .did (byte-identical).
    // This is the typed-decode link: the parsed type identifies the reply shape
    // the decode then uses.
    assert(
      result.symbolRetType === "record { symbol : text }",
      `symbolRetType === "record { symbol : text }" (got ${JSON.stringify(result.symbolRetType)})`
    );
    assert(
      result.queryOk === true,
      `queryOk === true (got ${result.queryOk}${result.error ? ", error=" + result.error : ""})`
    );
    // The typed decode: the reply decodes to "ICP" via the `record { symbol :
    // text }` type parseCandid identified.
    assert(
      result.symbol === "ICP",
      `symbol === "ICP" (got ${JSON.stringify(result.symbol)})`
    );
    assert(result.error == null, `no top-level error (got ${result.error})`);

    // R-3b WU-3 — callAnonymous full flow: validate → fetchCandid → encode
    // args → query → typed reply decode → {ok,result} envelope. The typed
    // decode (via the fetched candid's ret types) must yield {"symbol":"ICP"}.
    assert(
      result.callAnonOk === true,
      `callAnonOk === true (got ${result.callAnonOk}${result.callAnonError ? ", error=" + result.callAnonError : ""})`
    );
    assert(
      result.callAnonSymbol === "ICP",
      `callAnonSymbol === "ICP" (got ${JSON.stringify(result.callAnonSymbol)})`
    );

    // R-3b WU-4 — callAuthenticated with an Ed25519 identity: same flow but
    // the query is signed. `symbol()` doesn't require auth, so the result
    // matches the anonymous call — proving the agent creation + signing path.
    assert(
      result.callAuthOk === true,
      `callAuthOk === true (got ${result.callAuthOk}${result.callAuthError ? ", error=" + result.callAuthError : ""})`
    );
    assert(
      result.callAuthSymbol === "ICP",
      `callAuthSymbol === "ICP" (got ${JSON.stringify(result.callAuthSymbol)})`
    );

    if (failures.length) {
      console.error(`\n${failures.length} assertion(s) FAILED`);
      process.exit(1);
    }
    console.log("\nALL ASSERTIONS PASSED — fetchCandid + parseCandid + typed symbol decode + callAnonymous + callAuthenticated round-tripped browser→proxy→IC");
  } finally {
    if (browser) await browser.close().catch(() => {});
    server.close();
  }
})().catch((e) => {
  console.error("HARNESS FATAL:", e);
  process.exit(2);
});
