import {
  formatBytes,
  formatIcp,
  formatNumber,
  formatTimestamp,
  truncate,
} from "./format.js";
import type {
  IcpBatchResult,
  IcpCallResult,
  IcpMessageResult,
  IcpCallSpec,
  UiActionResult,
} from "./types.js";

export function icpCall(spec: IcpCallSpec): IcpCallResult {
  const s = spec ?? {};
  s.action = "call";
  return s as IcpCallResult;
}

export function icpBatch(calls?: unknown[]): IcpBatchResult {
  return { action: "batch", calls: calls ?? [] };
}

export function icpMessage(spec?: { text?: unknown; type?: unknown }): IcpMessageResult {
  const s = spec ?? {};
  return {
    action: "message",
    text: String(s.text ?? ""),
    type: String(s.type ?? "info"),
  };
}

export function icpUiList(spec?: {
  items?: unknown[];
  buttons?: unknown[];
}): UiActionResult {
  const s = spec ?? {};
  return {
    action: "ui",
    ui: {
      type: "list",
      items: s.items ?? [],
      buttons: s.buttons ?? [],
    },
  };
}

export function icpResultDisplay(spec?: Record<string, unknown>): UiActionResult {
  const s = spec ?? {};
  return {
    action: "ui",
    ui: { type: "result_display", props: s },
  };
}

export function icpSearchableList(spec?: {
  items?: unknown[];
  title?: unknown;
  searchable?: unknown;
}): UiActionResult {
  const s = spec ?? {};
  return {
    action: "ui",
    ui: {
      type: "list",
      props: {
        searchable: s.searchable !== false,
        items: s.items ?? [],
        title: String(s.title ?? "Results"),
      },
    },
  };
}

export function icpSection(spec?: {
  title?: unknown;
  content?: unknown;
}): UiActionResult {
  const s = spec ?? {};
  return {
    action: "ui",
    ui: {
      type: "section",
      props: {
        title: String(s.title ?? ""),
        content: String(s.content ?? ""),
      },
    },
  };
}

export function icpTable(data?: Record<string, unknown>): UiActionResult {
  return {
    action: "ui",
    ui: { type: "table", props: data ?? {} },
  };
}

export function icpFormatNumber(value: unknown, _decimals?: number): string {
  return formatNumber(value);
}

export function icpFormatIcp(value: unknown, decimals?: number): string {
  return formatIcp(value, decimals);
}

export function icpFormatTimestamp(value: unknown): string {
  return formatTimestamp(value);
}

export function icpFormatBytes(value: unknown): string {
  return formatBytes(value);
}

export function icpTruncate(text: unknown, _maxLen?: number): string {
  return truncate(text);
}

export function icpFilterItems(
  items: Record<string, unknown>[] | null | undefined,
  field: string,
  value: unknown,
): Record<string, unknown>[] {
  return (items ?? []).filter((it) =>
    String((it as Record<string, unknown> | null)?.[field] ?? "").includes(
      String(value),
    ),
  );
}

export function icpSortItems(
  items: Record<string, unknown>[] | null | undefined,
  field: string,
  ascending: boolean,
): Record<string, unknown>[] {
  return [...(items ?? [])].sort((a, b) => {
    const av = String((a as Record<string, unknown> | null)?.[field] ?? "");
    const bv = String((b as Record<string, unknown> | null)?.[field] ?? "");
    return ascending
      ? av < bv
        ? -1
        : av > bv
          ? 1
          : 0
      : av > bv
        ? -1
        : av < bv
          ? 1
          : 0;
  });
}

export function icpGroupBy(
  items: Record<string, unknown>[] | null | undefined,
  field: string,
): Record<string, Record<string, unknown>[]> {
  const groups: Record<string, Record<string, unknown>[]> = {};
  for (const it of items ?? []) {
    const key = String((it as Record<string, unknown> | null)?.[field] ?? "unknown");
    const bucket = groups[key];
    if (bucket) {
      bucket.push(it);
    } else {
      groups[key] = [it];
    }
  }
  return groups;
}

export const SDK_HOST_FUNCTIONS = [
  "icp_call",
  "icp_batch",
  "icp_message",
  "icp_ui_list",
  "icp_result_display",
  "icp_searchable_list",
  "icp_section",
  "icp_table",
  "icp_format_number",
  "icp_format_icp",
  "icp_format_timestamp",
  "icp_format_bytes",
  "icp_truncate",
  "icp_filter_items",
  "icp_sort_items",
  "icp_group_by",
] as const;
