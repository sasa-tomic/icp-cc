import { describe, it, expect } from "vitest";
import { newQuickJSWASMModuleFromVariant } from "quickjs-emscripten";
import variant from "@jitl/quickjs-singlefile-browser-release-sync";
import { LOCAL_HOST_BOOTSTRAP } from "@icp-cc/marketplace-sdk";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const FIXTURE = resolve(
  process.cwd(),
  "crates/icp_core/tests/fixtures/pilot_sample.bundle.js",
);
const BUNDLE = readFileSync(FIXTURE, "utf8");

let modulePromise: ReturnType<typeof newQuickJSWASMModuleFromVariant> | null = null;
async function getModule() {
  modulePromise ??= newQuickJSWASMModuleFromVariant(variant);
  return modulePromise;
}

type Ctx = Awaited<ReturnType<Awaited<ReturnType<typeof getModule>>["newContext"]>>;

async function run(ctx: Ctx, code: string): Promise<void> {
  const ran = await ctx.evalCode(code, "pilot-e2e.js");
  if ("error" in ran && ran.error) {
    const e = ctx.dump(ran.error);
    ran.error.dispose();
    throw new Error(`QuickJS error: ${JSON.stringify(e)}`);
  }
  ran.value.dispose();
}

async function evalJson<T = unknown>(ctx: Ctx, expr: string): Promise<T> {
  const ran = await ctx.evalCode(`JSON.stringify(${expr})`, "pilot-e2e.js");
  if ("error" in ran && ran.error) {
    const e = ctx.dump(ran.error);
    ran.error.dispose();
    throw new Error(`QuickJS error evaluating ${expr}: ${JSON.stringify(e)}`);
  }
  const out = ctx.getString(ran.value);
  ran.value.dispose();
  return JSON.parse(out) as T;
}

async function freshPilotVm(): Promise<Ctx> {
  const ctx = (await getModule()).newContext();
  await run(ctx, LOCAL_HOST_BOOTSTRAP);
  await run(ctx, BUNDLE);
  return ctx;
}

describe("pilot-sample bundle — runs end-to-end in REAL QuickJS", () => {
  it("exposes init/view/update as functions on globalThis", async () => {
    const ctx = await freshPilotVm();
    try {
      const types = await evalJson<string[]>(ctx, `[typeof init, typeof view, typeof update]`);
      expect(types).toEqual(["function", "function", "function"]);
    } finally {
      ctx.dispose();
    }
  });

  it("init returns the exact QuickJS runtime state shape with no effects", async () => {
    const ctx = await freshPilotVm();
    try {
      const res = await evalJson<{ state: Record<string, unknown>; effects: unknown[] }>(ctx, `init({})`);
      expect(res.effects).toEqual([]);
      expect(res.state).toEqual({
        count: 0,
        items: [],
        last: null,
        name: "",
        email: "",
        enabled: true,
        role: "user",
        showImage: false,
      });
    } finally {
      ctx.dispose();
    }
  });

  it("view renders a column containing a section titled 'UI Widgets Demo'", async () => {
    const ctx = await freshPilotVm();
    try {
      const initRes = await evalJson<{ state: Record<string, unknown> }>(ctx, `init({})`);
      const view = await evalJson<{ type: string; children: { type: string; props?: { title?: string } }[] }>(
        ctx,
        `view(${JSON.stringify(initRes.state)})`,
      );
      expect(view.type).toBe("column");
      expect(Array.isArray(view.children)).toBe(true);
      const section = view.children.find((c) => c.type === "section");
      expect(section, "view must contain a section node").toBeDefined();
      expect(section?.props?.title).toBe("UI Widgets Demo");
    } finally {
      ctx.dispose();
    }
  });

  it("update(inc) increments count to 1", async () => {
    const ctx = await freshPilotVm();
    try {
      const initRes = await evalJson<{ state: Record<string, unknown> }>(ctx, `init({})`);
      const upd = await evalJson<{ state: { count: number }; effects: unknown[] }>(
        ctx,
        `update(${JSON.stringify({ type: "inc" })}, ${JSON.stringify(initRes.state)})`,
      );
      expect(upd.state.count).toBe(1);
      expect(upd.effects).toEqual([]);
    } finally {
      ctx.dispose();
    }
  });

  it("update(load_sample) emits an icp_batch effect with gov + ledger items", async () => {
    const ctx = await freshPilotVm();
    try {
      const initRes = await evalJson<{ state: Record<string, unknown> }>(ctx, `init({})`);
      const upd = await evalJson<{
        state: Record<string, unknown>;
        effects: {
          kind: string;
          id: string;
          items: { label: string; kind: number; canister_id: string; method: string; args: string }[];
        }[];
      }>(ctx, `update(${JSON.stringify({ type: "load_sample" })}, ${JSON.stringify(initRes.state)})`);
      expect(upd.effects).toHaveLength(1);
      const effect = upd.effects[0]!;
      expect(effect.kind).toBe("icp_batch");
      expect(effect.id).toBe("load");
      expect(effect.items).toHaveLength(2);
      expect(effect.items[0]).toMatchObject({
        label: "gov",
        kind: 0,
        canister_id: "rrkah-fqaaa-aaaaa-aaaaq-cai",
        method: "get_pending_proposals",
        args: "()",
      });
      expect(effect.items[1]).toMatchObject({
        label: "ledger",
        kind: 0,
        canister_id: "ryjl3-tyaaa-aaaaa-aaaba-cai",
        method: "query_blocks",
        args: '{"start":0,"length":3}',
      });
    } finally {
      ctx.dispose();
    }
  });
});
