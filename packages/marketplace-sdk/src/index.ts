export { SDK_CONTRACT_VERSION } from "./version.js";
import type {
  IcpCallSpec,
  IcpCallResult,
  IcpBatchResult,
  IcpMessageResult,
  UiActionResult,
} from "./types.js";
export {
  CallMode,
  type CallModeValue,
  type Effect,
  type EffectItem,
  type IcpCallSpec,
  type IcpCallResult,
  type IcpBatchResult,
  type IcpMessageResult,
  type UiActionResult,
  type UiNode,
  type StrictUiNode,
  type ColumnNode,
  type RowNode,
  type SectionNode,
  type TextNode,
  type ButtonNode,
  type ToggleNode,
  type InputNode,
  type ActionResult,
  type State,
  type Msg,
  type Init,
  type View,
  type Update,
  type InitResult,
  type UpdateResult,
} from "./types.js";
export {
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
  icpFormatTimestamp,
  icpFormatBytes,
  icpTruncate,
  icpFilterItems,
  icpSortItems,
  icpGroupBy,
  SDK_HOST_FUNCTIONS,
} from "./helpers.js";
export {
  formatNumber,
  formatIcp,
  formatTimestamp,
  formatBytes,
  truncate,
} from "./format.js";
export { register, getInit, getView, getUpdate } from "./register.js";
export {
  installLocalHost,
  uninstallLocalHost,
  LOCAL_HOST_BOOTSTRAP,
  HOST_FUNCTION_NAMES,
  HOST_CAPABILITY_NAMES,
  type HostCapabilities,
  type LocalHost,
} from "./host.js";

declare global {
  function icp_call(spec: IcpCallSpec): IcpCallResult;
  function icp_batch(calls?: unknown[]): IcpBatchResult;
  function icp_message(spec?: { text?: unknown; type?: unknown }): IcpMessageResult;
  function icp_ui_list(spec?: { items?: unknown[]; buttons?: unknown[] }): UiActionResult;
  function icp_result_display(spec?: Record<string, unknown>): UiActionResult;
  function icp_searchable_list(spec?: { items?: unknown[]; title?: unknown; searchable?: unknown }): UiActionResult;
  function icp_section(spec?: { title?: unknown; content?: unknown }): UiActionResult;
  function icp_table(data?: Record<string, unknown>): UiActionResult;
  function icp_format_number(value: unknown, decimals?: number): string;
  function icp_format_icp(value: unknown, decimals?: number): string;
  function icp_format_timestamp(value: unknown): string;
  function icp_format_bytes(value: unknown): string;
  function icp_truncate(text: unknown, maxLen?: number): string;
  function icp_filter_items(items: Record<string, unknown>[] | null | undefined, field: string, value: unknown): Record<string, unknown>[];
  function icp_sort_items(items: Record<string, unknown>[] | null | undefined, field: string, ascending: boolean): Record<string, unknown>[];
  function icp_group_by(items: Record<string, unknown>[] | null | undefined, field: string): Record<string, Record<string, unknown>[]>;

  function icp_fetch(input: string, init?: unknown): Promise<unknown>;
  function icp_setTimeout(fn: () => void, ms?: number): number;
  function icp_url(url: string, base?: string): unknown;
  const icp_TextEncoder: { encode: (s: string) => unknown };
}
