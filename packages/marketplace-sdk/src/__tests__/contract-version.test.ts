import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { SDK_CONTRACT_VERSION } from "../version.js";

// Relative path from this test file
//   packages/marketplace-sdk/src/__tests__/contract-version.test.ts
// to the frozen golden at repo root parity/vectors.json.
// Four `../` climb __tests__ -> src -> marketplace-sdk -> packages -> repo root
// (the URL merge drops the filename before applying the first `..`).
const VECTORS_URL = new URL("../../../../parity/vectors.json", import.meta.url);
const VECTORS = JSON.parse(readFileSync(VECTORS_URL, "utf8")) as {
  schemaVersion: number;
  sdkContractVersion: string;
};

describe("contract-version triple-lock", () => {
  // The contract version is pinned by THREE independent sources, each enforced
  // in a different language/build:
  //
  //   leg 1 — Rust:    crates/icp_core SDK_CONTRACT_VERSION
  //                    (asserted by the Rust parity test reading this vector)
  //   leg 2 — Node:    packages/marketplace-sdk SDK_CONTRACT_VERSION
  //                    (asserted here, against the vector)
  //   leg 3 — Vector:  parity/vectors.json sdkContractVersion
  //
  // A version bump that touches only one or two of these legs MUST fail. This
  // test is leg 2: it proves the Node SDK string equals the vector's string,
  // which (transitively, via leg 1) equals the Rust constant.

  it("leg 2: SDK_CONTRACT_VERSION is a stable semver string", () => {
    expect(typeof SDK_CONTRACT_VERSION).toBe("string");
    expect(SDK_CONTRACT_VERSION).toMatch(/^\d+\.\d+\.\d+$/);
  });

  it("leg 2 == leg 3: Node SDK version equals the vector's sdkContractVersion", () => {
    expect(VECTORS.sdkContractVersion).toBe(SDK_CONTRACT_VERSION);
  });

  it("vector schema is the frozen schemaVersion 1 (guards a stale vector)", () => {
    expect(VECTORS.schemaVersion).toBe(1);
  });
});
