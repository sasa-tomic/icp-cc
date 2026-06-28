import { describe, it, expect } from "vitest";
import {
  formatNumber,
  formatIcp,
  formatTimestamp,
  formatBytes,
  truncate,
} from "../format.js";
import {
  icpFormatNumber,
  icpFormatIcp,
  icpFormatTimestamp,
  icpFormatBytes,
  icpTruncate,
} from "../helpers.js";

describe("format functions — Rust/Lua oracle values", () => {
  it("formatNumber(123.456, 2) === '123.456'", () => {
    expect(formatNumber(123.456)).toBe("123.456");
  });

  it("formatNumber coerces and falls back to 0", () => {
    expect(formatNumber("not a number")).toBe("0");
    expect(formatNumber(undefined)).toBe("0");
    expect(formatNumber(0)).toBe("0");
    expect(formatNumber(42)).toBe("42");
  });

  it("formatIcp(123456789, 8) === '1.23456789'", () => {
    expect(formatIcp(123456789, 8)).toBe("1.23456789");
  });

  it("formatIcp defaults decimals to 8", () => {
    expect(formatIcp(123456789)).toBe("1.23456789");
  });

  it("formatTimestamp(1634567890) === '1634567890'", () => {
    expect(formatTimestamp(1634567890)).toBe("1634567890");
  });

  it("formatBytes(1024) === '1024'", () => {
    expect(formatBytes(1024)).toBe("1024");
  });

  it("truncate returns the input stringified, unchanged", () => {
    expect(truncate("This is a very long text that should be truncated")).toBe(
      "This is a very long text that should be truncated",
    );
    expect(truncate(12345)).toBe("12345");
  });

  it("icp_format_* helpers mirror format functions", () => {
    expect(icpFormatNumber(123.456, 2)).toBe(formatNumber(123.456));
    expect(icpFormatIcp(123456789, 8)).toBe(formatIcp(123456789, 8));
    expect(icpFormatTimestamp(1634567890)).toBe(formatTimestamp(1634567890));
    expect(icpFormatBytes(1024)).toBe(formatBytes(1024));
    expect(icpTruncate("hello", 3)).toBe(truncate("hello"));
  });
});
