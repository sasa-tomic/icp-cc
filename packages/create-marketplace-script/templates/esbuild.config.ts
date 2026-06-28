import { build } from "esbuild";
import { noNodeBuiltinsPlugin } from "@icp-cc/create-marketplace-script/esbuild-no-node";

export async function buildBundle(options: { outfile?: string; write?: boolean } = {}) {
  return build({
    entryPoints: ["src/index.ts"],
    bundle: true,
    format: "iife",
    outfile: options.outfile ?? "dist/index.js",
    write: options.write ?? true,
    minify: false,
    sourcemap: false,
    platform: "neutral",
    target: "es2022",
    plugins: [noNodeBuiltinsPlugin()],
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await buildBundle();
  console.log("bundle written to dist/index.js");
}
