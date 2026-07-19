import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright config for the Phase C Tier B web e2e harness.
 *
 * The default flow:
 *   1. `npm run build` (or `just web-dev-build`) produces the static bundle at
 *      `apps/autorun_flutter/build/web/`.
 *   2. `npm run serve` (or any static HTTP server) serves it on :8099.
 *   3. `npm test` runs this Playwright config against http://127.0.0.1:8099/.
 *
 * CI variant: serve the bundle however the platform likes and override
 * `BASE_URL` via the env.
 */
const BASE_URL = process.env.BASE_URL ?? 'http://127.0.0.1:8099/';

export default defineConfig({
  testDir: './specs',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  // Vision-assertion flow: each spec navigates + takes a screenshot, then the
  // harness writes the screenshot to disk so the zai-vision MCP can pick it
  // up via `analyze_image`. Sequential — screenshots are cheap (~5s each) and
  // parallel runs would race the single Flutter canvas.
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
    // (see docs/OPEN_ISSUES.md #WEB-1). Playwright assertions must be visual
    // (screenshot → zai-vision) rather than DOM-based until Flutter ships
    // working programmatic semantics enablement.
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
