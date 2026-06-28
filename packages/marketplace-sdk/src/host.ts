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
} from "./helpers.js";

export interface HostCapabilities {
  icpFetch: (input: string, init?: unknown) => Promise<unknown>;
  icpSetTimeout: (fn: () => void, ms?: number) => number;
  icpUrl: (url: string, base?: string) => unknown;
  icpTextEncoder: { encode: (s: string) => unknown };
}

export interface LocalHost {
  capabilities: HostCapabilities;
}

export const HOST_FUNCTION_NAMES = [
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

export const HOST_CAPABILITY_NAMES = [
  "icp_fetch",
  "icp_setTimeout",
  "icp_url",
  "icp_TextEncoder",
] as const;

function defaultCapabilities(): HostCapabilities {
  return {
    icpFetch: () =>
      Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({}) }),
    icpSetTimeout: (fn, ms) => {
      Promise.resolve().then(() => fn());
      return ms ?? 0;
    },
    icpUrl: (url) => ({ href: url }),
    icpTextEncoder: {
      encode: (s) => {
        const bytes = new Uint8Array(s.length);
        for (let i = 0; i < s.length; i++) bytes[i] = s.charCodeAt(i) & 0xff;
        return bytes;
      },
    },
  };
}

export function installLocalHost(
  target: Record<string, unknown> = globalThis,
  capabilities: Partial<HostCapabilities> = {},
): LocalHost {
  const caps = { ...defaultCapabilities(), ...capabilities };
  target.icp_call = icpCall;
  target.icp_batch = icpBatch;
  target.icp_message = icpMessage;
  target.icp_ui_list = icpUiList;
  target.icp_result_display = icpResultDisplay;
  target.icp_searchable_list = icpSearchableList;
  target.icp_section = icpSection;
  target.icp_table = icpTable;
  target.icp_format_number = icpFormatNumber;
  target.icp_format_icp = icpFormatIcp;
  target.icp_format_timestamp = icpFormatTimestamp;
  target.icp_format_bytes = icpFormatBytes;
  target.icp_truncate = icpTruncate;
  target.icp_filter_items = icpFilterItems;
  target.icp_sort_items = icpSortItems;
  target.icp_group_by = icpGroupBy;
  target.icp_fetch = caps.icpFetch;
  target.icp_setTimeout = caps.icpSetTimeout;
  target.icp_url = caps.icpUrl;
  target.icp_TextEncoder = caps.icpTextEncoder;
  return { capabilities: caps };
}

export function uninstallLocalHost(
  target: Record<string, unknown> = globalThis,
): void {
  for (const name of HOST_FUNCTION_NAMES) delete target[name];
  for (const name of HOST_CAPABILITY_NAMES) delete target[name];
}

export const LOCAL_HOST_BOOTSTRAP = `
globalThis.icp_call = function(spec){ spec = spec || {}; spec.action = "call"; return spec; };
globalThis.icp_batch = function(calls){ return { action: "batch", calls: calls || [] }; };
globalThis.icp_message = function(spec){ spec = spec || {}; return { action: "message", text: String(spec.text ?? ""), type: String(spec.type ?? "info") }; };
globalThis.icp_ui_list = function(spec){ spec = spec || {}; return { action: "ui", ui: { type: "list", items: spec.items ?? [], buttons: spec.buttons ?? [] } }; };
globalThis.icp_result_display = function(spec){ return { action: "ui", ui: { type: "result_display", props: spec ?? {} } }; };
globalThis.icp_searchable_list = function(spec){ spec = spec || {}; return { action: "ui", ui: { type: "list", props: { searchable: spec.searchable !== false, items: spec.items ?? [], title: String(spec.title ?? "Results") } } }; };
globalThis.icp_section = function(spec){ spec = spec || {}; return { action: "ui", ui: { type: "section", props: { title: String(spec.title ?? ""), content: String(spec.content ?? "") } } }; };
globalThis.icp_table = function(data){ return { action: "ui", ui: { type: "table", props: data ?? {} } }; };
globalThis.icp_format_number = function(value){ return String(Number(value) || 0); };
globalThis.icp_format_icp = function(value, decimals){ var v = Number(value) || 0; var d = decimals ?? 8; return String(v / Math.pow(10, d)); };
globalThis.icp_format_timestamp = function(value){ return String(Number(value) || 0); };
globalThis.icp_format_bytes = function(value){ return String(Number(value) || 0); };
globalThis.icp_truncate = function(text){ return String(text); };
globalThis.icp_filter_items = function(items, field, value){ return (items || []).filter(function(it){ return String((it ? it[field] : undefined) ?? "").includes(String(value)); }); };
globalThis.icp_sort_items = function(items, field, ascending){ return [].concat(items || []).sort(function(a, b){ var av = String((a ? a[field] : undefined) ?? ""); var bv = String((b ? b[field] : undefined) ?? ""); return ascending ? (av < bv ? -1 : av > bv ? 1 : 0) : (av > bv ? -1 : av < bv ? 1 : 0); }); };
globalThis.icp_group_by = function(items, field){ return (items || []).reduce(function(g, it){ var key = String((it ? it[field] : undefined) ?? "unknown"); if(!g[key]) g[key] = []; g[key].push(it); return g; }, {}); };
`;
