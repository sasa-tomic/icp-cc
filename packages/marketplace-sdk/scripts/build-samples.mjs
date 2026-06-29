#!/usr/bin/env node
import { build } from "esbuild";
import { noNodeBuiltinsPlugin } from "@icp-cc/create-marketplace-script/esbuild-no-node";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { writeFileSync, mkdirSync } from "node:fs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "../../..");
const ENTRY = resolve(__dirname, "../samples/pilot-sample.ts");
const OUTFILE = resolve(ROOT, "crates/icp_core/tests/fixtures/pilot_sample.bundle.js");

export const PILOT_ENTRY = ENTRY;
export const PILOT_OUTFILE = OUTFILE;

export function pilotBundleOptions() {
  return {
    absWorkingDir: resolve(__dirname, ".."),
    entryPoints: [ENTRY],
    bundle: true,
    format: "iife",
    platform: "browser",
    target: "es2022",
    write: false,
    sourcemap: false,
    legalComments: "none",
    logLevel: "warning",
    plugins: [noNodeBuiltinsPlugin()],
  };
}

export async function buildPilotBundle() {
  const result = await build(pilotBundleOptions());
  const out = result.outputFiles?.[0];
  if (!out || typeof out.text !== "string") {
    throw new Error("build-samples: esbuild produced no output");
  }
  return out.text;
}

async function main() {
  const text = await buildPilotBundle();
  mkdirSync(dirname(OUTFILE), { recursive: true });
  writeFileSync(OUTFILE, text, "utf8");
  const committed = readFileSync(OUTFILE, "utf8");
  if (committed !== text) {
    throw new Error(`build-samples: write verification failed for ${OUTFILE}`);
  }
  process.stdout.write(`wrote ${OUTFILE} (${Buffer.byteLength(text)} bytes)\n`);
}

const invokedDirectly =
  process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedDirectly) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
