// R-3 shared headless-Chromium harness helpers.
//
// Factored out of `verify.js` (WU-1) so the parity probes (WU-2/WU-3/WU-4)
// reuse the same serve-static-build + launch-Chromium + poll-document.title
// pipeline. The probe entrypoint publishes its JSON result to document.title;
// the caller gets back the parsed object plus diagnostics (browser console).
//
// NEVER background-launches a browser/Xvfb: callers run this under a foreground
// `timeout` (see justfile `verify-quickjs-web*`).
const { chromium } = require("playwright");
const http = require("http");
const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const BUILD_DIR = path.join(REPO_ROOT, "apps/autorun_flutter/build/web");

/**
 * Serve BUILD_DIR over HTTP on 127.0.0.1, launch headless Chromium, navigate to
 * the probe page, poll document.title until it parses as JSON (matcher), and
 * resolve with the parsed result + diagnostics.
 *
 * @param {object} opts
 * @param {number} opts.port         Listen port (default 8754).
 * @param {string} opts.titleMatcher Substring that identifies the probe JSON in
 *                                  document.title (the probe publishes a
 *                                  distinct marker per suite).
 * @param {number} opts.titleTimeoutMs  Max ms to wait for the title (default 60s).
 * @returns {Promise<{result: object, title: string, diagnostics: object,
 *                    consoleLines: string[]}>}
 */
async function runProbe(opts) {
  const port = opts.port || 8754;
  const titleMatcher = opts.titleMatcher;
  const titleTimeoutMs = opts.titleTimeoutMs || 60000;
  const url = `http://127.0.0.1:${port}/`;

  if (!fs.existsSync(path.join(BUILD_DIR, "index.html"))) {
    throw new Error(
      `BUILD_DIR/index.html not found: ${BUILD_DIR}. Run the matching ` +
        `\`flutter build web --target=lib/<probe>.dart\` first.`
    );
  }

  const server = http.createServer(staticHandler);
  await new Promise((r) => server.listen(port, "127.0.0.1", r));

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    // The production app + probes pull in the `passkeys` plugin (web init throws
    // + window.close() when the Corbado SDK bundle.js is absent). Stub it so the
    // page survives — passkey availability is unrelated to R-3 script execution.
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

    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });

    let title = "";
    const deadline = Date.now() + titleTimeoutMs;
    while (Date.now() < deadline) {
      title = await page.title();
      if (title.startsWith("{") && title.includes(titleMatcher)) break;
      await page.waitForTimeout(250);
    }

    const diagnostics = await page.evaluate(() => ({
      qjsGlobal: typeof window.__quickjsEmscripten,
      qjsVersion: window.__quickjsEmscripten && window.__quickjsEmscripten.version,
      probeDiv:
        !!document.getElementById("probe-result") ||
        !!document.getElementById("parity-result"),
    }));

    let result;
    try {
      result = JSON.parse(title);
    } catch (e) {
      throw new Error(
        `document.title is not probe JSON (matcher=${titleMatcher}): ${title.slice(0, 240)}`
      );
    }
    return { result, title, diagnostics, consoleLines };
  } finally {
    if (browser) await browser.close().catch(() => {});
    server.close();
  }
}

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

module.exports = { runProbe, BUILD_DIR, REPO_ROOT };
