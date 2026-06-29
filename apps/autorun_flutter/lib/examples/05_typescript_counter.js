"use strict";
(() => {
  function init() {
    return { state: { count: 0 }, effects: [] };
  }

  function view(state) {
    return {
      type: "column",
      children: [
        { type: "text", props: { text: "Count: " + (state.count || 0) } },
        {
          type: "button",
          props: { label: "Increment", action: { type: "inc" } },
        },
        {
          type: "button",
          props: { label: "Reset", action: { type: "reset" } },
        },
      ],
    };
  }

  function update(msg, state) {
    if (msg.type === "inc") {
      return { state: { count: (state.count || 0) + 1 }, effects: [] };
    }
    if (msg.type === "reset") {
      return { state: { count: 0 }, effects: [] };
    }
    return { state: state, effects: [] };
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
