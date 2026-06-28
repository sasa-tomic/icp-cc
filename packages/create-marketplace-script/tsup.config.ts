import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts", "src/scaffold.ts", "src/esbuild-no-node.ts", "src/quickjs-harness.ts"],
  format: ["esm"],
  dts: true,
  sourcemap: true,
  clean: true,
  target: "es2022",
  platform: "node",
});
