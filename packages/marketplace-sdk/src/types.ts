export type State = Record<string, unknown>;

export interface Msg {
  type: string;
  id?: string;
  ok?: boolean;
  data?: unknown;
  error?: string;
  [key: string]: unknown;
}

export const CallMode = {
  Query: 0,
  Update: 1,
  Composite: 2,
} as const;

export type CallModeValue = (typeof CallMode)[keyof typeof CallMode];

export interface EffectItem {
  label: string;
  mode: CallModeValue;
  canister_id: string;
  method: string;
  args: unknown;
}

export type Effect =
  | { kind: "icp_call"; id: string; items: [EffectItem] }
  | { kind: "icp_batch"; id: string; items: EffectItem[] };

export interface IcpCallSpec {
  canister?: string;
  method?: string;
  args?: unknown;
  [key: string]: unknown;
}

export interface IcpCallResult {
  action: "call";
  canister?: string;
  method?: string;
  args?: unknown;
  [key: string]: unknown;
}

export interface IcpBatchResult {
  action: "batch";
  calls: unknown[];
}

export interface IcpMessageResult {
  action: "message";
  text: string;
  type: string;
}

export interface UiNode {
  type: string;
  props?: Record<string, unknown>;
  children?: UiNode[];
  items?: unknown[];
  buttons?: unknown[];
}

export interface UiActionResult {
  action: "ui";
  ui: UiNode;
}

export type ActionResult =
  | IcpCallResult
  | IcpBatchResult
  | IcpMessageResult
  | UiActionResult
  | string;

export interface InitResult<S extends State = State> {
  state: S;
  effects: Effect[];
}

export interface UpdateResult<S extends State = State> {
  state: S;
  effects: Effect[];
}

export type Init<S extends State = State> = (arg: unknown) => InitResult<S>;
export type View<S extends State = State> = (state: S) => ActionResult | UiNode;
export type Update<S extends State = State> = (msg: Msg, state: S) => UpdateResult<S>;

export type ColumnNode = { type: "column"; children: UiNode[]; props?: Record<string, unknown> };
export type RowNode = { type: "row"; children: UiNode[]; props?: Record<string, unknown> };
export type SectionNode = { type: "section"; props: { title: string; content?: string }; children?: UiNode[] };
export type TextNode = { type: "text"; props: { text: string } };
export type ButtonNode = { type: "button"; props: { label: string; msgType?: string } };
export type ToggleNode = { type: "toggle"; props: { label: string; checked: boolean; msgTypeOn?: string; msgTypeOff?: string } };
export type InputNode = { type: "input"; props: { placeholder?: string; value?: string; msgType?: string } };

export type StrictUiNode =
  | ColumnNode
  | RowNode
  | SectionNode
  | TextNode
  | ButtonNode
  | ToggleNode
  | InputNode
  | { type: "list"; props: { items: unknown[]; title?: string; searchable?: boolean } }
  | { type: "result_display"; props: Record<string, unknown> }
  | { type: "table"; props: Record<string, unknown> };
