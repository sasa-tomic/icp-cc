import { describe, it, expect } from "vitest";
import { newQuickJSWASMModuleFromVariant } from "quickjs-emscripten";
import variant from "@jitl/quickjs-singlefile-browser-release-sync";
import { LOCAL_HOST_BOOTSTRAP } from "@icp-cc/marketplace-sdk";
import {
  icpCall,
  icpBatch,
  icpMessage,
  icpUiList,
  icpResultDisplay,
  icpSearchableList,
  icpSection,
  icpTable,
  icpFormatNumber,
  icpFormatIcp,
  icpFilterItems,
  icpSortItems,
  icpGroupBy,
} from "@icp-cc/marketplace-sdk";

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value !== null && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const k of Object.keys(value as Record<string, unknown>).sort()) {
      out[k] = sortKeys((value as Record<string, unknown>)[k]);
    }
    return out;
  }
  return value;
}
const canon = (v: unknown) => JSON.stringify(sortKeys(v));

let modulePromise: ReturnType<typeof newQuickJSWASMModuleFromVariant> | null = null;
async function qjsEvalJson(expr: string): Promise<string> {
  const mod = await (modulePromise ??= newQuickJSWASMModuleFromVariant(variant));
  const ctx = mod.newContext();
  try {
    const ran = await ctx.evalCode(`${LOCAL_HOST_BOOTSTRAP}\nJSON.stringify(${expr})`, "parity.js");
    if ("error" in ran && ran.error) {
      const e = ctx.dump(ran.error);
      ran.error.dispose();
      throw new Error(`QuickJS error evaluating ${expr}: ${JSON.stringify(e)}`);
    }
    const value = ran.value;
    if (!value) throw new Error("no value");
    const out = ctx.getString(value);
    value.dispose();
    return out;
  } finally {
    ctx.dispose();
  }
}

describe("LOCAL_HOST_BOOTSTRAP (QuickJS) === helpers.ts (V8) — parity guard", () => {
  async function assertParity(expr: string, reference: unknown): Promise<void> {
    const quickjsJson = await qjsEvalJson(expr);
    expect(canon(JSON.parse(quickjsJson))).toBe(canon(reference));
  }

  it("icp_call", async () => {
    const arg = { canister: "rrkah-fqaaa-aaaaa-aaaaq-cai", method: "get_balance", args: "()" };
    await assertParity(`icp_call(${JSON.stringify(arg)})`, icpCall({ ...arg }));
  });

  it("icp_batch", async () => {
    const arg = [{ canister: "a", method: "m", args: "()" }];
    await assertParity(`icp_batch(${JSON.stringify(arg)})`, icpBatch(arg));
  });

  it("icp_message", async () => {
    await assertParity(`icp_message(${JSON.stringify({ text: "hi", type: "warn" })})`, icpMessage({ text: "hi", type: "warn" }));
  });

  it("icp_ui_list", async () => {
    await assertParity(`icp_ui_list(${JSON.stringify({ items: ["a", "b"] })})`, icpUiList({ items: ["a", "b"] }));
  });

  it("icp_result_display", async () => {
    await assertParity(`icp_result_display(${JSON.stringify({ ok: true })})`, icpResultDisplay({ ok: true }));
  });

  it("icp_searchable_list (default searchable)", async () => {
    await assertParity(`icp_searchable_list(${JSON.stringify({ items: [1] })})`, icpSearchableList({ items: [1] }));
  });

  it("icp_section", async () => {
    await assertParity(`icp_section(${JSON.stringify({ title: "T", content: "C" })})`, icpSection({ title: "T", content: "C" }));
  });

  it("icp_table", async () => {
    await assertParity(`icp_table(${JSON.stringify({ headers: ["a"] })})`, icpTable({ headers: ["a"] }));
  });

  it("icp_format_number / icp_format_icp", async () => {
    await assertParity(`icp_format_number(123.456, 2)`, icpFormatNumber(123.456, 2));
    await assertParity(`icp_format_icp(123456789, 8)`, icpFormatIcp(123456789, 8));
  });

  it("icp_filter_items", async () => {
    const items = [{ name: "Alice", city: "New York" }, { name: "Bob", city: "London" }];
    await assertParity(`icp_filter_items(${JSON.stringify(items)}, "city", "New York")`, icpFilterItems(items, "city", "New York"));
  });

  it("icp_sort_items", async () => {
    const items = [{ name: "Charlie", age: 30 }, { name: "Alice", age: 25 }];
    await assertParity(`icp_sort_items(${JSON.stringify(items)}, "name", true)`, icpSortItems(items, "name", true));
  });

  it("icp_group_by", async () => {
    const items = [{ name: "Alice", city: "NY" }, { name: "Bob", city: "LDN" }];
    await assertParity(`icp_group_by(${JSON.stringify(items)}, "city")`, icpGroupBy(items, "city"));
  });
});
