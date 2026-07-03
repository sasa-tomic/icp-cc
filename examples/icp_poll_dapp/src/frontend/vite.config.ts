import { defineConfig } from "vite";
import { resolve } from "node:path";
import { readFileSync } from "node:fs";

// dfx sets DFX_NETWORK ("local" | "ic") during `dfx deploy`. We read it at
// build time and inject it as a build-time constant so the frontend knows which
// host to talk to. Defaults to the local replica (port 4943).
const network = process.env.DFX_NETWORK === "ic" ? "ic" : "local";

// Single source of truth for the backend canister id. Tried in order:
//   1. CANISTER_ID_BACKEND env var (dfx sets this during `dfx deploy` — raw id)
//   2. .dfx/local/canister_ids.json  (dfx 0.29.x local network output)
//   3. canister_ids.local.json        (canonical source, per the dapp spec)
// dfx's id files have the shape { backend: { local: "...", ic: "..." } }.
function readBackendCanisterId(): string {
  if (process.env.CANISTER_ID_BACKEND) return process.env.CANISTER_ID_BACKEND;

  const pick = (obj: unknown): string => {
    if (!obj || typeof obj !== "object") return "";
    const b = (obj as { backend?: unknown }).backend;
    if (typeof b === "string") return b;
    if (b && typeof b === "object") {
      const env = network === "ic" ? "ic" : "local";
      const v = (b as Record<string, string>)[env];
      if (typeof v === "string") return v;
    }
    return "";
  };

  for (const file of [".dfx/local/canister_ids.json", "canister_ids.local.json"]) {
    try {
      const id = pick(JSON.parse(readFileSync(resolve(process.cwd(), file), "utf8")));
      if (id) return id;
    } catch {
      // file not present yet — try the next source
    }
  }
  console.warn(
    `[vite.config] WARNING: backend canister id not found. ` +
      `Run \`dfx deploy\` first, or create canister_ids.local.json.`,
  );
  return "";
}

export default defineConfig({
  // index.html + the TS entry live under src/frontend.
  root: resolve(process.cwd(), "src/frontend"),
  // Load .env (dfx output_env_file) from the dapp root.
  envDir: process.cwd(),
  build: {
    // dfx.json `source: ["dist"]` reads from <dapp-root>/dist.
    outDir: resolve(process.cwd(), "dist"),
    emptyOutDir: true,
  },
  define: {
    __DFX_NETWORK__: JSON.stringify(network),
    __BACKEND_CANISTER_ID__: JSON.stringify(readBackendCanisterId()),
  },
});
