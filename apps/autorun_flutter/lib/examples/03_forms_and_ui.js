// TypeScript/QuickJS bundle: exercises the rich UI widget surface
// (text_field, toggle, select, image, section, list, row, button).
// Ports the widget coverage of the advanced-UI demo.
"use strict";
(() => {
  function init() {
    return {
      state: {
        name: "",
        email: "",
        notifications: true,
        role: "user",
        showImage: false,
        items: [],
      },
      effects: [],
    };
  }

  function view(state) {
    var children = [];

    children.push({
      type: "section",
      props: { title: "Form Widgets" },
      children: [
        {
          type: "text_field",
          props: {
            label: "Name",
            placeholder: "Enter your name",
            value: state.name || "",
            on_change: { type: "set_name" },
          },
        },
        {
          type: "text_field",
          props: {
            label: "Email",
            placeholder: "Enter your email",
            value: state.email || "",
            keyboard_type: "email",
            on_change: { type: "set_email" },
          },
        },
        {
          type: "toggle",
          props: {
            label: "Notifications",
            value: state.notifications === true,
            on_change: { type: "set_notifications" },
          },
        },
        {
          type: "select",
          props: {
            label: "Role",
            value: state.role || "user",
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
            { type: "button", props: { label: "Reset", on_press: { type: "reset" } } },
            { type: "button", props: { label: "Submit", on_press: { type: "submit" } } },
          ],
        },
      ],
    });

    if (state.showImage) {
      children.push({
        type: "section",
        props: { title: "Image" },
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
              { title: "Name", subtitle: state.name || "(empty)" },
              { title: "Email", subtitle: state.email || "(empty)" },
              { title: "Notifications", subtitle: String(state.notifications) },
              { title: "Role", subtitle: state.role || "user" },
            ],
          },
        },
      ],
    });

    var submitted = state.items || [];
    if (Array.isArray(submitted) && submitted.length > 0) {
      children.push({
        type: "section",
        props: { title: "Submissions" },
        children: [{ type: "list", props: { items: submitted } }],
      });
    }

    return { type: "column", children: children };
  }

  function update(msg, state) {
    var t = (msg && msg.type) || "";

    if (t === "set_name") {
      return { state: { ...state, name: typeof msg.value === "string" ? msg.value : "" }, effects: [] };
    }
    if (t === "set_email") {
      return { state: { ...state, email: typeof msg.value === "string" ? msg.value : "" }, effects: [] };
    }
    if (t === "set_notifications") {
      return { state: { ...state, notifications: msg.value === true }, effects: [] };
    }
    if (t === "set_role") {
      return { state: { ...state, role: typeof msg.value === "string" ? msg.value : "user" }, effects: [] };
    }
    if (t === "toggle_image") {
      return { state: { ...state, showImage: msg.value === true }, effects: [] };
    }
    if (t === "reset") {
      return { state: init().state, effects: [] };
    }
    if (t === "submit") {
      var entry = {
        title: state.name || "(no name)",
        subtitle: state.email || "(no email)",
      };
      var items = (state.items || []).slice();
      items.push(entry);
      return { state: { ...state, items: items }, effects: [] };
    }

    return { state: state, effects: [] };
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
