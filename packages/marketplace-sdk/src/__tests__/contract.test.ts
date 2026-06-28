import { describe, it, expect } from "vitest";
import { SDK_CONTRACT_VERSION } from "../version.js";
import type {
  Effect,
  EffectItem,
  Init,
  Msg,
  State,
  Update,
  View,
  EffectKindValue,
  IcpCallResult,
  IcpBatchResult,
} from "../types.js";
import { EffectKind } from "../types.js";

describe("SDK contract", () => {
  it("exports SDK_CONTRACT_VERSION as a stable semver string", () => {
    expect(typeof SDK_CONTRACT_VERSION).toBe("string");
    expect(SDK_CONTRACT_VERSION).toMatch(/^\d+\.\d+\.\d+$/);
    expect(SDK_CONTRACT_VERSION).toBe("0.1.0");
  });

  it("EffectKind maps query/update/composite to 0/1/2", () => {
    const values: EffectKindValue[] = [EffectKind.Query, EffectKind.Update, EffectKind.Composite];
    expect(values).toEqual([0, 1, 2]);
  });

  it("Effect/EffectItem shapes type-check against the contract", () => {
    const item: EffectItem = {
      label: "ledger",
      kind: EffectKind.Query,
      canister_id: "ryjl3-tyaaa-aaaaa-aaaba-cai",
      method: "query_blocks",
      args: '{"start":0,"length":3}',
    };
    const effect: Effect = { kind: "icp_batch", id: "load", items: [item] };
    expect(effect.kind).toBe("icp_batch");
    expect(effect.items).toHaveLength(1);
  });

  it("Init/View/Update signatures type-check", () => {
    const init: Init = (arg) => {
      const count = (arg as { count?: number } | null)?.count ?? 0;
      return { state: { count }, effects: [] };
    };
    const view: View = (state) => {
      const s = state as { count: number };
      return { type: "text", props: { text: String(s.count) } };
    };
    const update: Update = (msg: Msg, state) => {
      const s = state as { count: number };
      if (msg.type === "inc") return { state: { count: s.count + 1 }, effects: [] };
      return { state: s, effects: [] };
    };

    expect(typeof init).toBe("function");
    expect(typeof view).toBe("function");
    expect(typeof update).toBe("function");

    const initResult = init({ count: 5 });
    expect((initResult.state as { count: number }).count).toBe(5);
    const _check: State = initResult.state;
    expect(_check).toBeDefined();
  });

  it("icp_call result type carries passthrough fields", () => {
    const result: IcpCallResult = {
      action: "call",
      canister: "rrkah-fqaaa-aaaaa-aaaaq-cai",
      method: "get_balance",
      args: "()",
    };
    expect(result.action).toBe("call");
  });

  it("icp_batch result type is action+calls", () => {
    const result: IcpBatchResult = { action: "batch", calls: [] };
    expect(result.calls).toEqual([]);
  });
});
