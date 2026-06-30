// Minimal TypeScript/QuickJS bundle: a greeting + counter.
// Self-contained IIFE — the host runs QuickJS, not a TS compiler.
// Contract: expose globalThis.init / view / update.
"use strict";
(() => {
  function init() {
    return { state: { count: 0, name: "" }, effects: [] };
  }

  function view(state) {
    const count = state.count || 0;
    const name = typeof state.name === "string" ? state.name : "";
    const greeting = name.length > 0 ? "Hello, " + name + "!" : "Hello, world!";
    return {
      type: "column",
      children: [
        { type: "text", props: { text: greeting } },
        { type: "text", props: { text: "Count: " + count } },
        {
          type: "row",
          children: [
            { type: "button", props: { label: "Increment", on_press: { type: "inc" } } },
            { type: "button", props: { label: "Reset", on_press: { type: "reset" } } },
          ],
        },
        {
          type: "text_field",
          props: {
            label: "Your name",
            placeholder: "Enter your name",
            value: name,
            on_change: { type: "set_name" },
          },
        },
      ],
    };
  }

  function update(msg, state) {
    const t = (msg && msg.type) || "";
    if (t === "inc") {
      return { state: { ...state, count: (state.count || 0) + 1 }, effects: [] };
    }
    if (t === "reset") {
      return { state: { ...state, count: 0 }, effects: [] };
    }
    if (t === "set_name") {
      return { state: { ...state, name: typeof msg.value === "string" ? msg.value : "" }, effects: [] };
    }
    return { state: state, effects: [] };
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
