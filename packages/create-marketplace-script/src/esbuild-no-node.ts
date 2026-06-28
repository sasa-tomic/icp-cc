import type { Plugin } from "esbuild";

export const NODE_BUILTIN_MODULES = [
  "assert",
  "buffer",
  "child_process",
  "cluster",
  "console",
  "constants",
  "crypto",
  "dgram",
  "diagnostics_channel",
  "dns",
  "domain",
  "events",
  "fs",
  "http",
  "http2",
  "https",
  "module",
  "net",
  "os",
  "path",
  "perf_hooks",
  "process",
  "punycode",
  "querystring",
  "readline",
  "repl",
  "stream",
  "string_decoder",
  "sys",
  "timers",
  "tls",
  "trace_events",
  "tty",
  "url",
  "util",
  "v8",
  "vm",
  "wasi",
  "worker_threads",
  "zlib",
] as const;

export interface NoNodeOptions {
  additionalBanned?: string[];
}

export function noNodeBuiltinsPlugin(options: NoNodeOptions = {}): Plugin {
  const banned = new Set<string>([
    ...NODE_BUILTIN_MODULES,
    ...(options.additionalBanned ?? []),
  ]);
  return {
    name: "no-node-builtins",
    setup(build) {
      const check = (spec: string): string | null => {
        const stripped = spec.startsWith("node:") ? spec.slice(5) : spec;
        if (banned.has(stripped)) return stripped;
        return null;
      };
      build.onResolve({ filter: /^node:/ }, (args) => {
        const hit = check(args.path);
        if (hit) {
          throw new Error(
            `[no-node-builtins] Forbidden Node builtin "${hit}" imported at "${args.importer}". Marketplace scripts must not use Node built-ins.`,
          );
        }
        return null;
      });
      build.onResolve({ filter: /.*/ }, (args) => {
        const hit = check(args.path);
        if (hit) {
          throw new Error(
            `[no-node-builtins] Forbidden Node builtin "${hit}" imported at "${args.importer}". Marketplace scripts must not use Node built-ins.`,
          );
        }
        return null;
      });
    },
  };
}

export interface BuiltinGlobalRestriction {
  name: string;
  message: string;
}

export const FORBIDDEN_BUILTIN_GLOBALS: BuiltinGlobalRestriction[] = [
  { name: "fetch", message: "Use the SDK icp_fetch host capability instead of the built-in fetch." },
  { name: "setTimeout", message: "Use the SDK icp_setTimeout host capability instead of the built-in setTimeout." },
  { name: "setInterval", message: "Use the SDK host capability instead of the built-in setInterval." },
  { name: "URL", message: "Use the SDK icp_url host capability instead of the built-in URL." },
  { name: "URLSearchParams", message: "Use the SDK host capability instead of the built-in URLSearchParams." },
  { name: "TextEncoder", message: "Use the SDK icp_TextEncoder host capability instead of the built-in TextEncoder." },
  { name: "TextDecoder", message: "Use the SDK host capability instead of the built-in TextDecoder." },
];

export function assertNoNodeBuiltinsInBundle(bundleSource: string): string[] {
  const offenders: string[] = [];
  const patterns = [
    /\brequire\s*\(\s*["'](?:node:)?(fs|path|crypto|process|child_process|os|http|https|net|stream|buffer|timers)["']/g,
    /\bfrom\s*["'](?:node:)?(fs|path|crypto|process|child_process|os|http|https|net|stream|buffer|timers)["']/g,
  ];
  for (const pattern of patterns) {
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(bundleSource)) !== null) {
      const mod = match[1];
      if (mod) offenders.push(mod);
    }
  }
  return offenders;
}
