import js from "@eslint/js";
import globals from "globals";

export default [
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: { ...globals.browser },
    },
    rules: {
      "no-restricted-globals": [
        "error",
        { name: "fetch", message: "Use the SDK icp_fetch host capability, not the built-in fetch." },
        { name: "setTimeout", message: "Use the SDK icp_setTimeout host capability, not the built-in setTimeout." },
        { name: "setInterval", message: "Use the SDK host capability, not the built-in setInterval." },
        { name: "URL", message: "Use the SDK icp_url host capability, not the built-in URL." },
        { name: "URLSearchParams", message: "Use the SDK host capability, not the built-in URLSearchParams." },
        { name: "TextEncoder", message: "Use the SDK icp_TextEncoder host capability, not the built-in TextEncoder." },
        { name: "TextDecoder", message: "Use the SDK host capability, not the built-in TextDecoder." },
      ],
      "no-restricted-syntax": [
        "error",
        {
          selector: "ImportDeclaration[source.value=/^(node:)?(fs|path|crypto|process|child_process|os|http|https|net|stream|buffer|timers)(\\/|$)/]",
          message: "Marketplace scripts must not import Node built-in modules.",
        },
      ],
    },
  },
];
