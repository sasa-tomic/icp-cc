import { register } from "@icp-cc/marketplace-sdk";
import type { State, Msg } from "@icp-cc/marketplace-sdk";

interface CounterState extends State {
  count: number;
}

function init(arg: unknown): { state: CounterState; effects: [] } {
  const count = (arg as { count?: number } | null)?.count ?? 0;
  return { state: { count }, effects: [] };
}

function view(state: CounterState) {
  return icp_section({
    title: "Counter",
    content: `Count is ${icp_format_number(state.count)}`,
  });
}

function update(msg: Msg, state: CounterState): { state: CounterState; effects: [] } {
  if (msg.type === "inc") return { state: { ...state, count: state.count + 1 }, effects: [] };
  if (msg.type === "dec") return { state: { ...state, count: state.count - 1 }, effects: [] };
  return { state, effects: [] };
}

register(init, view, update);
