/**
 * Phase C Tier B — Playwright smoke against the built Flutter Web bundle.
 *
 * WHY THIS EXISTS (see docs/specs/2026-07-19-e2e-and-ux-continuation.md
 * Pivot 1, Tier B)
 *
 * Tier A (`flutter test -d chrome` + substrate fakes) covers 7 flows against
 * the REAL app on Chromium — fast and DRY with the desktop suite. But it has
 * one gap: TestWidgetsFlutterBinding is NOT a real browser. The conditional
 * export picks the IO JsonDocumentStore, plugin round-trips go to mocks, and
 * the Web pure-Dart crypto path runs on the Dart VM (not via canvaskit JS).
 *
 * Tier B closes that gap by driving the REAL built bundle (canvaskit + all
 * the real Web platform code paths) via Playwright. The catch is that Flutter
 * Web's a11y tree is NOT auto-enabled in headless Chromium (WEB-1), so DOM
 * assertions are unavailable. The workaround is visual: each spec navigates,
 * takes a screenshot, and the harness sends the screenshot to the
 * `zai-vision` MCP via `analyze_image` for layout/visibility assertions.
 *
 * RUNNING
 *
 *   # 1. Start the dev backend (Phase C-Tier-A already assumes this).
 *   just api-dev-up
 *
 *   # 2. Build + serve the bundle.
 *   cd apps/autorun_flutter/web_e2e_playwright
 *   npm install
 *   npm run install-browsers
 *   npm run build     # writes ../build/web
 *   npm run serve &   # serves on :8099
 *
 *   # 3. Run Playwright (sequentially — see playwright.config.ts).
 *   npm test
 *
 *   # 4. Vision-assert the screenshots (NOT in this spec — the harness is
 *   #    intentionally not coupled to zai-vision here; pair the screenshots
 *   #    with `zai-vision_analyze_image` calls from the orchestrator-verifier
 *   #    role).
 *
 * Screenshots land in `docs/specs/ux_screenshots/e2e_web_playwright/`. The
 * orchestrator-verifier sends each one to `zai-vision_analyze_image` with a
 * prompt like "is this the ICP Autorun first-run wizard?" — visual proof
 * that the bundle boots and renders the expected UI.
 */
import { test, expect } from '@playwright/test';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

const SHOT_DIR = resolve(__dirname, '..', '..', '..', '..', 'docs', 'specs',
  'ux_screenshots', 'e2e_web_playwright');

test.beforeAll(() => mkdirSync(SHOT_DIR, { recursive: true }));

/**
 * Wait for the Flutter canvaskit canvas to actually paint.
 *
 * `flt-glass-pane` is mounted by the engine bootstrap as an EMPTY custom
 * element; canvaskit later attaches a SHADOW ROOT containing a `<canvas>`
 * inside `<flt-scene-host><flt-scene><flt-canvas-container>`. We have to
 * probe via `evaluate` (Playwright's `locator` doesn't pierce closed shadow
 * roots by default) and check the canvas's bounding rect for non-trivial
 * geometry as proof of paint.
 */
async function waitForFlutterPainted(page: import('@playwright/test').Page,
  timeoutMs = 30_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const painted = await page.evaluate(() => {
      const glass = document.querySelector('flt-glass-pane') as
        (HTMLElement & { shadowRoot?: ShadowRoot | null }) | null;
      const canvas = glass?.shadowRoot?.querySelector('canvas');
      if (!canvas) return false;
      const rect = canvas.getBoundingClientRect();
      return rect.width >= 1024 && rect.height >= 600;
    });
    if (painted) return;
    await page.waitForTimeout(250);
  }
  throw new Error(`Flutter canvas did not paint within ${timeoutMs}ms`);
}

/**
 * Read the canvas's bounding box (post-paint) for sanity assertions.
 * Returns via the same shadow-root-piercing evaluate as
 * [waitForFlutterPainted].
 */
async function flutterCanvasBox(page: import('@playwright/test').Page):
  Promise<{ width: number; height: number } | null> {
  return page.evaluate(() => {
    const glass = document.querySelector('flt-glass-pane') as
      (HTMLElement & { shadowRoot?: ShadowRoot | null }) | null;
    const canvas = glass?.shadowRoot?.querySelector('canvas');
    if (!canvas) return null;
    const rect = canvas.getBoundingClientRect();
    return { width: rect.width, height: rect.height };
  });
}

test('bundle boots — flutter canvas mounts', async ({ page }) => {
  page.on('pageerror', err => console.log('PAGEERROR:', err.message));
  await page.goto('/');
  // Flutter Web mounts a `<flt-glass-pane>` shadow-DOM host once the engine
  // initialises; canvaskit then attaches a shadow root with the real <canvas>.
  // Wait for the canvas to have non-trivial geometry as proof of paint.
  await waitForFlutterPainted(page, 30_000);
  await page.waitForTimeout(2_000); // let the first frames settle.
  await page.screenshot({
    path: `${SHOT_DIR}/01_boot.png`,
    fullPage: true,
  });
  // Sanity: re-check the canvas box after the settle wait.
  const box = await flutterCanvasBox(page);
  expect(box, 'canvas must have geometry').not.toBeNull();
  expect(box!.width, 'canvas must be ≥1024 wide').toBeGreaterThanOrEqual(1024);
  expect(box!.height, 'canvas must be ≥600 tall').toBeGreaterThanOrEqual(600);
});

test('first-run wizard renders', async ({ page }) => {
  await page.goto('/');
  await waitForFlutterPainted(page, 30_000);
  // The wizard pushes after the post-frame ensureLoaded chain completes
  // (ProfileController + ScriptController load → showFirstRunSetupIfNeeded).
  // Give it generous wall time on a cold boot.
  await page.waitForTimeout(8_000);
  await page.screenshot({
    path: `${SHOT_DIR}/02_wizard.png`,
    fullPage: true,
  });
  // Vision assertion is intentionally out-of-band: the screenshot is the
  // artifact; the orchestrator-verifier (or a CI step) sends it to
  // `zai-vision_analyze_image` to assert "wizard is visible, has 'Set up
  // profile' text, ICP branding, etc." (see WEB-1 for why DOM-based
  // assertions are unavailable in headless Chromium).
});
