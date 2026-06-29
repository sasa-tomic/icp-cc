import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { canonical } from "./canonical.js";
import {
  icpBatch,
  icpCall,
  icpFilterItems,
  icpFormatBytes,
  icpFormatIcp,
  icpFormatNumber,
  icpFormatTimestamp,
  icpGroupBy,
  icpMessage,
  icpResultDisplay,
  icpSearchableList,
  icpSection,
  icpSortItems,
  icpTable,
  icpTruncate,
  icpUiList,
} from "../helpers.js";

interface ParityCase {
  id: string;
  helper: string;
  args: unknown[];
  expectedJs: unknown;
  expectedLua: unknown;
  notes?: string;
}

interface ParityVector {
  schemaVersion: number;
  sdkContractVersion: string;
  notes: string;
  cases: ParityCase[];
}

// Relative path from this test file
//   packages/marketplace-sdk/src/__tests__/parity.vectors.test.ts
// to the frozen golden at repo root
//   parity/vectors.json
// `new URL(rel, fileUrl)` performs an RFC-3986 merge: the base path is taken
// up to its last "/" (so the filename segment is dropped before any `..` is
// applied). Four `../` therefore climb:
//   __tests__ -> src -> marketplace-sdk -> packages -> repo root
// and then `parity/vectors.json` lands at /<repo>/parity/vectors.json.
const VECTORS_URL = new URL("../../../../parity/vectors.json", import.meta.url);
const VECTORS = JSON.parse(readFileSync(VECTORS_URL, "utf8")) as ParityVector;

// Map the runtime snake_case helper names (as authored in the vector) to the
// camelCase TypeScript exports. This mirrors `installLocalHost()` in
// `src/host.ts` 1:1 — the same binding the QuickJS bundle sees at runtime — so
// this harness exercises the exact code path scripts depend on.
const HELPERS: Record<string, (...args: unknown[]) => unknown> = {
  icp_call: icpCall,
  icp_batch: icpBatch,
  icp_message: icpMessage,
  icp_ui_list: icpUiList,
  icp_result_display: icpResultDisplay,
  icp_searchable_list: icpSearchableList,
  icp_section: icpSection,
  icp_table: icpTable,
  icp_format_number: icpFormatNumber,
  icp_format_icp: icpFormatIcp,
  icp_format_timestamp: icpFormatTimestamp,
  icp_format_bytes: icpFormatBytes,
  icp_truncate: icpTruncate,
  icp_filter_items: icpFilterItems,
  icp_sort_items: icpSortItems,
  icp_group_by: icpGroupBy,
};

describe("parity vectors — Node SDK matches the frozen golden (Rust-host == Node-SDK)", () => {
  it("vector declares the frozen schemaVersion 1", () => {
    expect(VECTORS.schemaVersion).toBe(1);
  });

  it("every case references a mapped helper (no silent skips)", () => {
    for (const c of VECTORS.cases) {
      expect(
        HELPERS[c.helper],
        `helper "${c.helper}" referenced by case "${c.id}" is not in the Node map`,
      ).toBeTruthy();
    }
  });

  it("vector case count is 24 (catches accidental truncation)", () => {
    expect(VECTORS.cases.length).toBe(24);
  });

  for (const c of VECTORS.cases) {
    it(`parity: ${c.id} (${c.helper})`, () => {
      const fn = HELPERS[c.helper];
      // Defensive: if a future vector adds a helper without a map entry, fail
      // loudly here rather than silently passing.
      expect(fn, `helper "${c.helper}" is not mapped (case ${c.id})`).toBeTruthy();
      // args is positional JSON; spread it directly into the call.
      const actual = fn(...c.args);
      // expectedJs is authoritative. Canonicalize both via recursive key sort
      // so key order is irrelevant (matches the Rust parity test's policy).
      expect(canonical(actual)).toBe(canonical(c.expectedJs));
    });
  }
});
