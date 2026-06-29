#!/usr/bin/env node
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..");
const CONFIG_PATH = join(__dirname, "deps-allowlist.json");

function loadConfig() {
  const raw = readFileSync(CONFIG_PATH, "utf8");
  const cfg = JSON.parse(raw);
  if (typeof cfg.devAllowlist !== "string" || !cfg.devAllowlist) {
    throw new Error(`deps-allowlist.json: devAllowlist must be a non-empty regex string`);
  }
  const runtime = Array.isArray(cfg.runtimeAllowlist) ? cfg.runtimeAllowlist : [];
  const globs = Array.isArray(cfg.packageGlobs) && cfg.packageGlobs.length > 0
    ? cfg.packageGlobs
    : ["packages/*"];
  return { devAllowlist: cfg.devAllowlist, runtimeAllowlist: new Set(runtime), packageGlobs: globs };
}

function expandGlobs(root, globs) {
  const dirs = [];
  for (const g of globs) {
    const abs = join(root, g);
    const base = abs.includes("*") ? g.slice(0, g.indexOf("*")) : g;
    const baseAbs = join(root, base.endsWith("/") ? base : base + "/");
    if (!existsSync(baseAbs)) continue;
    const seg = g.slice(g.indexOf("*") + 1);
    for (const entry of readdirSync(baseAbs)) {
      const full = join(baseAbs, entry);
      if (!statSync(full).isDirectory()) continue;
      if (seg && !entry.endsWith(seg)) continue;
      const pkg = join(full, "package.json");
      if (existsSync(pkg)) dirs.push(pkg);
    }
  }
  return dirs;
}

function check() {
  const { devAllowlist, runtimeAllowlist, packageGlobs } = loadConfig();
  const devRe = new RegExp(devAllowlist);
  const manifests = expandGlobs(REPO_ROOT, packageGlobs);
  if (manifests.length === 0) {
    console.error(`[check-deps-allowlist] no package.json found under ${packageGlobs.join(", ")}`);
    return 1;
  }

  const violations = [];
  for (const manifest of manifests) {
    const pkg = JSON.parse(readFileSync(manifest, "utf8"));
    const name = pkg.name ?? manifest;
    const deps = pkg.dependencies ?? {};
    const devDeps = pkg.devDependencies ?? {};

    for (const dep of Object.keys(deps)) {
      if (!runtimeAllowlist.has(dep)) {
        violations.push(
          `${name}: runtime dependency "${dep}" is forbidden. Packages must be zero-dep at runtime (scripts bundle to self-contained IIFEs). Remove it from "dependencies". [${manifest}]`,
        );
      }
    }
    for (const dep of Object.keys(devDeps)) {
      if (!devRe.test(dep)) {
        violations.push(
          `${name}: dev dependency "${dep}" is not on the allowlist (regex: ${devAllowlist}). [${manifest}]`,
        );
      }
    }
  }

  if (violations.length > 0) {
    console.error("[check-deps-allowlist] FAILED — dependency policy violations:\n");
    for (const v of violations) console.error(`  ✗ ${v}`);
    console.error(`\n${violations.length} violation(s). See scripts/deps-allowlist.json for the policy.`);
    return 1;
  }

  console.log(`[check-deps-allowlist] OK — ${manifests.length} package(s) conform to the dependency policy.`);
  return 0;
}

process.exit(check());
