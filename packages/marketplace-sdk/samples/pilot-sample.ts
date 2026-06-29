import { EffectKind, register } from "@icp-cc/marketplace-sdk";
import type {
  Effect,
  EffectItem,
  InitResult,
  Msg,
  State,
  UiNode,
  UpdateResult,
} from "@icp-cc/marketplace-sdk";

interface FormItem {
  title: string;
  subtitle: string;
}

interface PilotState extends State {
  count: number;
  items: FormItem[];
  last: unknown;
  name: string;
  email: string;
  enabled: boolean;
  role: string;
  showImage: boolean;
}

function init(_arg: unknown): InitResult<PilotState> {
  return {
    state: {
      count: 0,
      items: [],
      last: null,
      name: "",
      email: "",
      enabled: true,
      role: "user",
      showImage: false,
    },
    effects: [],
  };
}

function view(state: PilotState): UiNode {
  const children: UiNode[] = [];

  children.push({
    type: "section",
    props: { title: "UI Widgets Demo" },
    children: [
      { type: "text", props: { text: `Counter: ${state.count ?? 0}` } },
      {
        type: "text_field",
        props: {
          label: "Name",
          placeholder: "Enter your name",
          value: state.name ?? "",
          on_change: { type: "set_name" },
        },
      },
      {
        type: "text_field",
        props: {
          label: "Email",
          placeholder: "Enter your email",
          value: state.email ?? "",
          keyboard_type: "email",
          on_change: { type: "set_email" },
        },
      },
      {
        type: "toggle",
        props: {
          label: "Enable features",
          value: state.enabled === true,
          on_change: { type: "set_enabled" },
        },
      },
      {
        type: "select",
        props: {
          label: "Role",
          value: state.role ?? "user",
          options: [
            { value: "user", label: "User" },
            { value: "admin", label: "Administrator" },
            { value: "moderator", label: "Moderator" },
          ],
          on_change: { type: "set_role" },
        },
      },
      {
        type: "toggle",
        props: {
          label: "Show image",
          value: state.showImage === true,
          on_change: { type: "toggle_image" },
        },
      },
      {
        type: "row",
        children: [
          { type: "button", props: { label: "Increment", on_press: { type: "inc" } } },
          { type: "button", props: { label: "Load ICP samples", on_press: { type: "load_sample" } } },
        ],
      },
    ],
  });

  if (state.showImage) {
    children.push({
      type: "section",
      props: { title: "Image Demo" },
      children: [
        {
          type: "image",
          props: {
            src: "https://picsum.photos/seed/icp-demo/300/200.jpg",
            width: 300,
            height: 200,
            fit: "cover",
          },
        },
      ],
    });
  }

  children.push({
    type: "section",
    props: { title: "Current Values" },
    children: [
      {
        type: "list",
        props: {
          items: [
            { title: "Name", subtitle: state.name ?? "(empty)" },
            { title: "Email", subtitle: state.email ?? "(empty)" },
            { title: "Enabled", subtitle: String(state.enabled) },
            { title: "Role", subtitle: state.role ?? "user" },
            { title: "Show Image", subtitle: String(state.showImage) },
          ],
        },
      },
    ],
  });

  const items = state.items ?? [];
  if (Array.isArray(items) && items.length > 0) {
    children.push({
      type: "section",
      props: { title: "Loaded results" },
      children: [{ type: "list", props: { items } }],
    });
  }

  return { type: "column", children };
}

function update(msg: Msg, state: PilotState): UpdateResult<PilotState> {
  const t = msg?.type ?? "";

  if (t === "set_name") {
    return { state: { ...state, name: typeof msg.value === "string" ? msg.value : "" }, effects: [] };
  }
  if (t === "set_email") {
    return { state: { ...state, email: typeof msg.value === "string" ? msg.value : "" }, effects: [] };
  }
  if (t === "set_enabled") {
    return { state: { ...state, enabled: msg.value === true }, effects: [] };
  }
  if (t === "set_role") {
    return { state: { ...state, role: typeof msg.value === "string" ? msg.value : "user" }, effects: [] };
  }
  if (t === "toggle_image") {
    return { state: { ...state, showImage: msg.value === true }, effects: [] };
  }

  if (t === "inc") {
    return { state: { ...state, count: (state.count ?? 0) + 1 }, effects: [] };
  }

  if (t === "load_sample") {
    const gov: EffectItem = {
      label: "gov",
      kind: EffectKind.Query,
      canister_id: "rrkah-fqaaa-aaaaa-aaaaq-cai",
      method: "get_pending_proposals",
      args: "()",
    };
    const ledger: EffectItem = {
      label: "ledger",
      kind: EffectKind.Query,
      canister_id: "ryjl3-tyaaa-aaaaa-aaaba-cai",
      method: "query_blocks",
      args: '{"start":0,"length":3}',
    };
    const effect: Effect = { kind: "icp_batch", id: "load", items: [gov, ledger] };
    return { state, effects: [effect] };
  }

  if (t === "effect/result" && msg.id === "load") {
    const items: FormItem[] = [];
    if (msg.ok) {
      const data = (msg.data ?? {}) as Record<string, unknown>;
      for (const key of Object.keys(data)) {
        const v = data[key];
        const subtitle = typeof v === "object" && v !== null ? JSON.stringify(v) : String(v);
        items.push({ title: String(key), subtitle });
      }
    } else {
      items.push({ title: "Error", subtitle: String(msg.error ?? "unknown error") });
    }
    return { state: { ...state, items }, effects: [] };
  }

  return { state: { ...state, last: msg }, effects: [] };
}

register(init, view, update);
