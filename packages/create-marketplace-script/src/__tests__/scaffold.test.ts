import { describe, it, expect, afterEach } from "vitest";
import { rmSync, readFileSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";
import { scaffoldProject, TEMPLATE_FILES } from "../scaffold.js";
import { noNodeBuiltinsPlugin, assertNoNodeBuiltinsInBundle } from "../esbuild-no-node.js";
import { evalBundleInQuickJS } from "../quickjs-harness.js";
import { LOCAL_HOST_BOOTSTRAP } from "@icp-cc/marketplace-sdk";

const TMP = fileURLToPath(new URL("./.tmp-scaffold", import.meta.url));
const ROOT = resolve(fileURLToPath(new URL("../../../../", import.meta.url)));
const WORKSPACE_NODE_MODULES = join(ROOT, "node_modules");
const VITEST_BIN = join(WORKSPACE_NODE_MODULES, ".bin", "vitest");

afterEach(() => {
  if (existsSync(TMP)) rmSync(TMP, { recursive: true, force: true });
});

describe("scaffoldProject()", () => {
  it("writes every template file into the target directory", () => {
    const result = scaffoldProject(TMP, "my-counter");
    expect(result.name).toBe("my-counter");
    for (const file of TEMPLATE_FILES) {
      expect(existsSync(join(TMP, file))).toBe(true);
    }
  });

  it("substitutes {{NAME}} in package.json", () => {
    scaffoldProject(TMP, "my-counter");
    const pkg = JSON.parse(readFileSync(join(TMP, "package.json"), "utf8"));
    expect(pkg.name).toBe("my-counter");
  });

  it("rejects invalid names", () => {
    expect(() => scaffoldProject(TMP, "Bad Name!")).toThrow(/Invalid project name/);
  });

  it("refuses to overwrite an existing directory", () => {
    scaffoldProject(TMP, "my-counter");
    expect(() => scaffoldProject(TMP, "other")).toThrow(/already exists/);
  });
});

describe("scaffolded sample — builds to a single Node-free IIFE and runs in QuickJS", () => {
  it("bundles, contains no Node builtins, and exposes init/view/update as globals", async () => {
    scaffoldProject(TMP, "my-counter");

    const result = await build({
      entryPoints: [join(TMP, "src/index.ts")],
      bundle: true,
      format: "iife",
      write: false,
      platform: "neutral",
      target: "es2022",
      absWorkingDir: TMP,
      nodePaths: [WORKSPACE_NODE_MODULES],
      plugins: [noNodeBuiltinsPlugin()],
      logLevel: "silent",
    });

    const bundleSource = result.outputFiles[0]?.text ?? "";
    expect(bundleSource.length).toBeGreaterThan(0);
    expect(bundleSource).toMatch(/^(?:"use strict";\n)?\(\(\) => \{/);
    expect(bundleSource).toMatch(/\}\)\(\);\n?$/);
    expect(bundleSource).not.toMatch(/^\s*import\b/m);
    expect(bundleSource).not.toMatch(/^\s*export\b/m);

    const offenders = assertNoNodeBuiltinsInBundle(bundleSource);
    expect(offenders).toEqual([]);

    const evalResult = await evalBundleInQuickJS({
      bootstrap: LOCAL_HOST_BOOTSTRAP,
      bundleSource,
      updateMsg: { type: "inc" },
    });

    expect(evalResult.lifecycleTypes).toEqual(["function", "function", "function"]);

    const init = evalResult.initResult as { state: { count: number }; effects: unknown[] };
    expect(init.state.count).toBe(0);
    expect(init.effects).toEqual([]);

    const view = evalResult.viewResult as {
      action: string;
      ui: { type: string; props: { title: string; content: string } };
    };
    expect(view.action).toBe("ui");
    expect(view.ui.type).toBe("section");
    expect(view.ui.props.title).toBe("Counter");
    expect(view.ui.props.content).toBe("Count is 0");

    const update = evalResult.updateResult as { state: { count: number } };
    expect(update.state.count).toBe(1);
  });

  it("the no-node plugin rejects a source that imports fs", async () => {
    scaffoldProject(TMP, "my-counter");
    await expect(
      build({
        stdin: { contents: `import { readFileSync } from "node:fs";\nconsole.log(readFileSync);` },
        bundle: true,
        format: "iife",
        write: false,
        absWorkingDir: TMP,
        plugins: [noNodeBuiltinsPlugin()],
        logLevel: "silent",
      }),
    ).rejects.toThrow(/Forbidden Node builtin "fs"/);
  });

  it("the scaffolded project's own test suite passes (sample runs in real QuickJS)", () => {
    scaffoldProject(TMP, "my-counter");
    const result = spawnSync(VITEST_BIN, ["run", "--reporter=default"], {
      cwd: TMP,
      encoding: "utf-8",
      timeout: 90000,
      env: { ...process.env, CI: "1", FORCE_COLOR: "0" },
    });
    const body = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
    expect(result.status, body).toBe(0);
    expect(body).toContain("2 passed");
  });
});
