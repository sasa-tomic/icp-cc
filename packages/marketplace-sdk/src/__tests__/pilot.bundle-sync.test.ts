import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { buildPilotBundle } from "../../scripts/build-samples.mjs";

const FIXTURE = resolve(
  process.cwd(),
  "crates/icp_core/tests/fixtures/pilot_sample.bundle.js",
);

describe("pilot bundle sync (drift guard)", () => {
  it("committed fixture is byte-identical to a fresh esbuild build", async () => {
    const fresh = await buildPilotBundle();
    const committed = readFileSync(FIXTURE, "utf8");
    expect(fresh).toBe(committed);
  });

  it("bundle is a single IIFE with no import/export and no Node builtins", async () => {
    const source = readFileSync(FIXTURE, "utf8");
    expect(source.trim().startsWith('"use strict";\n(() => {')).toBe(true);
    expect(source.trim().endsWith("})();")).toBe(true);
    expect(/^\s*(import|export)\b/m.test(source)).toBe(false);
    expect(/require\(["'](?:node:)?(?:fs|path|crypto|process|child_process|os|http|https|net|stream|buffer|timers)["']/.test(source)).toBe(false);
  });
});
