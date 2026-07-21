/**
 * WEB-1 — Passkey-on-Web Playwright spec.
 *
 * Drives the built Flutter Web bundle
 * (`flutter build web --target=tool/web_probe_passkey_main.dart`) through the
 * full passkey registration flow against the REAL backend, with the browser's
 * WebAuthn surface satisfied headlessly by Playwright 1.61+'s
 * `browserContext.credentials` virtual authenticator API.
 *
 * Two specs cover the success + failure contract:
 *
 *   1. `passkey registration round-trip succeeds with virtual authenticator`:
 *      installs a virtual authenticator for RP ID `localhost`, loads the probe
 *      page, polls `document.title` for the JSON result, and asserts every
 *      check (`username_chosen`, `keypair`, `register_account`,
 *      `register_passkey`, `list_passkeys`) is `pass: true` AND the backend
 *      has the passkey (count=1, id matches).
 *
 *   2. `passkey registration fails loudly without virtual authenticator`:
 *      loads the probe page with `?expectFailure=1` and NO virtual
 *      authenticator. Asserts the probe completes with the expected-failure
 *      verdict (loud WebAuthn timeout), not a silent hang.
 *
 * Every failure dumps: page URL, browser console lines, page errors,
 * screenshot path, and the probe's full JSON result — never a bare
 * "test failed".
 *
 * The bundle + dedicated backend (with WEBAUTHN_RP_ORIGIN matching the page
 * origin) are brought up by the justfile `e2e-web-passkey` recipe — this spec
 * assumes both are already running. Run via `just e2e-web-passkey`.
 */
import { test, expect } from '@playwright/test';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

const SHOT_DIR = resolve(__dirname, '..', '..', '..', '..', 'docs', 'specs',
  'ux_screenshots', 'e2e_web_passkey');
mkdirSync(SHOT_DIR, { recursive: true });

const BASE_URL = process.env.BASE_URL ?? 'http://localhost:8099/';
const TITLE_TIMEOUT_MS = Number(process.env.TITLE_TIMEOUT_MS ?? 90_000);

interface Check {
  name: string;
  pass: boolean;
  detail: string;
}
interface ProbeResult {
  allPassed: boolean;
  phase: string;
  checks: Check[];
  apiEndpoint?: string;
  rpOrigin?: string;
}

/**
 * Load the probe page, install/omit the virtual authenticator per
 * `withAuthenticator`, and poll document.title for the probe's JSON result.
 *
 * On any failure: dumps URL, console lines, page errors, screenshot path,
 * and the raw document.title to stderr — never a silent throw.
 */
async function runProbe(
  page: import('@playwright/test').Page,
  context: import('@playwright/test').BrowserContext,
  withAuthenticator: boolean,
  expectFailure: boolean,
): Promise<{ result: ProbeResult; consoleLines: string[]; pageErrors: string[] }> {
  if (withAuthenticator) {
    // Playwright 1.61+ modern API (the recommended cross-browser path).
    if (!context.credentials ||
        typeof context.credentials.create !== 'function' ||
        typeof context.credentials.install !== 'function') {
      throw new Error(
        'Playwright context.credentials API unavailable. Need Playwright ' +
        '>= 1.61 — install with `npm install playwright@^1.61` from the ' +
        'web_e2e_playwright/ directory.'
      );
    }
    // Seed a virtual passkey for the page's origin (RP ID `localhost`).
    // `create()` registers the credential; `install()` arms the context
    // with a virtual authenticator that satisfies any subsequent
    // navigator.credentials.{create,get} call for that RP ID.
    await context.credentials.create('localhost');
    await context.credentials.install();
  }

  const consoleLines: string[] = [];
  const pageErrors: string[] = [];
  page.on('console', (m) => consoleLines.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => pageErrors.push(`${e.stack || e.message}`));

  const url = expectFailure ? `${BASE_URL}?expectFailure=1` : BASE_URL;
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30_000 });

  // Poll document.title for the probe's JSON result.
  const deadline = Date.now() + TITLE_TIMEOUT_MS;
  let title = '';
  while (Date.now() < deadline) {
    title = await page.title();
    if (title.startsWith('{') && title.includes('"phase"')) break;
    await page.waitForTimeout(250);
  }

  if (!title.startsWith('{')) {
    // Loud failure: dump everything we have before throwing.
    await page.screenshot({ path: `${SHOT_DIR}/no-result.png`, fullPage: true });
    console.error('WEB-1 spec: probe did not publish JSON.');
    console.error(`  URL: ${url}`);
    console.error(`  document.title: ${title.slice(0, 240)}`);
    console.error(`  console lines (${consoleLines.length}):`);
    for (const l of consoleLines) console.error(`    ${l}`);
    console.error(`  page errors (${pageErrors.length}):`);
    for (const l of pageErrors) console.error(`    ${l}`);
    console.error(`  screenshot: ${SHOT_DIR}/no-result.png`);
    throw new Error(`probe did not publish JSON within ${TITLE_TIMEOUT_MS}ms`);
  }

  let result: ProbeResult;
  try {
    result = JSON.parse(title);
  } catch (e) {
    throw new Error(
      `document.title is not probe JSON: ${title.slice(0, 240)}`
    );
  }
  return { result, consoleLines, pageErrors };
}

function assertProbeWitness(
  tag: string,
  result: ProbeResult,
  consoleLines: string[],
  pageErrors: string[],
) {
  // Always log the full result + console as diagnostics — useful in CI logs
  // for both green and red runs.
  console.log(`[${tag}] phase=${result.phase} allPassed=${result.allPassed}`);
  for (const c of result.checks) {
    console.log(`  [${c.pass ? 'PASS' : 'FAIL'}] ${c.name}: ${c.detail}`);
  }
  if (pageErrors.length) {
    console.warn(`[${tag}] page errors (${pageErrors.length}):`);
    for (const l of pageErrors) console.warn(`  ${l}`);
  }
  // Suppress console-line spam on green (the probe's own result line is enough).
  if (!result.allPassed && consoleLines.length) {
    console.warn(`[${tag}] console lines:`);
    for (const l of consoleLines) console.warn(`  ${l}`);
  }
}

test('passkey registration round-trip succeeds with virtual authenticator', async ({
  page, context,
}) => {
  const { result, consoleLines, pageErrors } = await runProbe(
    page, context, /* withAuthenticator */ true, /* expectFailure */ false,
  );
  await page.screenshot({
    path: `${SHOT_DIR}/01_positive_path.png`,
    fullPage: true,
  });
  assertProbeWitness('positive', result, consoleLines, pageErrors);

  // Per-check assertions — name them so CI output points at the failing one.
  expect(result.phase, 'probe phase').toBe('complete');
  expect(result.allPassed, 'allPassed').toBe(true);
  const byName = Object.fromEntries(result.checks.map((c) => [c.name, c]));
  expect(byName.username_chosen?.pass, 'username_chosen').toBe(true);
  expect(byName.keypair?.pass, 'keypair (real Ed25519 on Web)').toBe(true);
  expect(byName.register_account?.pass, 'register_account (signed POST)').toBe(true);
  expect(byName.register_passkey?.pass, 'register_passkey (WebAuthn round-trip)').toBe(true);
  expect(byName.list_passkeys?.pass, 'list_passkeys (backend verification)').toBe(true);

  // Defense-in-depth: assert the actual passkey id landed in the backend.
  const listDetail = byName.list_passkeys?.detail ?? '';
  expect(listDetail, 'list_passkeys count=1').toMatch(/count=1/);
  expect(listDetail, 'list_passkeys expectedMatch=true').toMatch(/expectedMatch=true/);
});

test('passkey registration fails loudly without virtual authenticator', async ({
  page, context,
}) => {
  const { result, consoleLines, pageErrors } = await runProbe(
    page, context, /* withAuthenticator */ false, /* expectFailure */ true,
  );
  await page.screenshot({
    path: `${SHOT_DIR}/02_negative_path.png`,
    fullPage: true,
  });
  assertProbeWitness('negative', result, consoleLines, pageErrors);

  // The probe MUST report the loud failure, not silently hang forever.
  expect(result.phase, 'phase').toBe('expect_failure');
  expect(result.allPassed, 'allPassed (expect-failure verdict)').toBe(true);

  // Specifically: the register_passkey check MUST have failed loudly with a
  // recognizable WebAuthn error (NotAllowed/SecurityError/TimeoutException).
  const regCheck = result.checks.find((c) => c.name === 'register_passkey');
  expect(regCheck, 'register_passkey check present').toBeTruthy();
  expect(regCheck!.pass, 'register_passkey.pass (must be false)').toBe(false);
  const detail = regCheck!.detail;
  expect(detail, 'register_passkey detail must mention WebAuthn or Timeout').toMatch(
    /WebAuthn|TimeoutException|NotAllowed|SecurityError/,
  );
});
