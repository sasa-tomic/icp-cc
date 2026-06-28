import { describe, it, expect } from "vitest";
import { evalBundleInQuickJS } from "@icp-cc/create-marketplace-script/quickjs-harness";
import { LOCAL_HOST_BOOTSTRAP } from "@icp-cc/marketplace-sdk";
import { buildBundle } from "../esbuild.config.js";

async function buildBundleSource(): Promise<string> {
  const result = await buildBundle({ write: false });
  const file = result.outputFiles[0];
  if (!file) throw new Error("esbuild produced no output");
  return file.text;
}

describe("counter app — runs in real QuickJS", () => {
  it("exposes init/view/update as globals after eval", async () => {
    const bundleSource = await buildBundleSource();
    const result = await evalBundleInQuickJS({
      bootstrap: LOCAL_HOST_BOOTSTRAP,
      bundleSource,
    });
    expect(result.lifecycleTypes).toEqual(["function", "function", "function"]);
  });

  it("init returns count 0, view renders a section, update increments", async () => {
    const bundleSource = await buildBundleSource();
    const result = await evalBundleInQuickJS({
      bootstrap: LOCAL_HOST_BOOTSTRAP,
      bundleSource,
      updateMsg: { type: "inc" },
    });

    expect((result.initResult as { state: { count: number } }).state.count).toBe(0);
    const view = result.viewResult as { action: string; ui: { type: string; props: { title: string; content: string } } };
    expect(view.action).toBe("ui");
    expect(view.ui.type).toBe("section");
    expect(view.ui.props.title).toBe("Counter");
    expect(view.ui.props.content).toBe("Count is 0");

    expect((result.updateResult as { state: { count: number } }).state.count).toBe(1);
  });
});
