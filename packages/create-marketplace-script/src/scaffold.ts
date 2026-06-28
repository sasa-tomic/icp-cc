import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const TEMPLATES_DIR = fileURLToPath(new URL("../templates/", import.meta.url));

export const TEMPLATE_FILES = [
  "package.json",
  "tsconfig.json",
  "esbuild.config.ts",
  "vitest.config.ts",
  "eslint.config.js",
  "src/index.ts",
  "src/index.test.ts",
] as const;

export interface ScaffoldResult {
  name: string;
  dir: string;
  files: string[];
}

const NAME_RE = /^(?:@[\da-z~-][\d.a-z_-]*\/)?[\da-z~-][\d.a-z_-]*$/;

export function assertValidName(name: string): void {
  if (!NAME_RE.test(name)) {
    throw new Error(
      `Invalid project name "${name}". Use lowercase letters, digits, '-', '_', '.', and optional '@scope/'.`,
    );
  }
}

export function renderTemplate(relativePath: string, name: string): string {
  const source = readFileSync(join(TEMPLATES_DIR, relativePath), "utf8");
  if (relativePath === "package.json") {
    return source.replaceAll("{{NAME}}", name);
  }
  return source;
}

export function scaffoldProject(targetDir: string, name: string): ScaffoldResult {
  assertValidName(name);
  const dir = resolve(targetDir);
  if (existsSync(dir)) {
    throw new Error(`Target directory already exists: ${dir}`);
  }
  mkdirSync(dir, { recursive: true });

  const written: string[] = [];
  for (const file of TEMPLATE_FILES) {
    const outPath = join(dir, file);
    mkdirSync(dirname(outPath), { recursive: true });
    writeFileSync(outPath, renderTemplate(file, name), "utf8");
    written.push(file);
  }
  return { name, dir, files: written };
}
