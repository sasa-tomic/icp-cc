import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright config for the web e2e harness (Tier B + WEB-1 passkey spec).
 *
 * The default flow:
 *   1. `npm run build` (or `just web-dev-build` / `just e2e-web-passkey`)
 *      produces the static bundle at `apps/autorun_flutter/build/web/`.
 *   2. `npm run serve` (or the justfile recipe) serves it on :8099.
 *   3. `npm test` runs this Playwright config against http://localhost:8099/.
 *
 * BASE_URL defaults to `localhost` (NOT 127.0.0.1) because the WEB-1 passkey
 * spec needs the WebAuthn RP ID (`localhost`) to match the page origin. The
 * boot smoke spec is origin-agnostic so it works against either host.
 *
 * CI variant: serve the bundle however the platform likes and override
 * `BASE_URL` via the env.
 */
const BASE_URL = process.env.BASE_URL ?? 'http://localhost:8099/';

export default defineConfig({
  testDir: './specs',
  // 120s per spec — the WEB-1 negative-path spec waits up to 20s for
  // `navigator.credentials.create` to time out before the probe publishes.
  // Boot smoke is ~10s.
  timeout: 120_000,
  expect: { timeout: 10_000 },
  // One Chromium at a time — parallel runs would race the single Flutter
  // canvas AND fight over the dedicated backend's RP origin.
  fullyParallel: false,
  workers: 1,
  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
  ],
  use: {
    baseURL: BASE_URL,
    headless: true,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    // Flutter canvaskit needs a real viewport; tiny viewports truncate the
    // canvas. Match the desktop kDesktopSize from e2e_driver.dart.
    viewport: { width: 1440, height: 900 },
    // The Flutter Web a11y tree is NOT auto-enabled in headless Chromium
    // (see docs/OPEN_ISSUES.md #WEB-1 for the historical investigation).
    // The WEB-1 RESOLUTION (Playwright 1.61+ virtual authenticator + the
    // passkey probe entrypoint) sidesteps this by isolating the passkey
    // flow into a Dart probe that publishes its result to document.title
    // (no DOM-tree walking required). The boot smoke spec is screenshot-only.
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
