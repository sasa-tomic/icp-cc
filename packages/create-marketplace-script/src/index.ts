#!/usr/bin/env node
import { resolve } from "node:path";
import { createInterface } from "node:readline/promises";
import { stdin, stdout } from "node:process";
import { scaffoldProject, assertValidName } from "./scaffold.js";

function parseArgs(argv: string[]): { name?: string; dir?: string } {
  const positional: string[] = [];
  for (const arg of argv.slice(2)) {
    if (arg.startsWith("-")) continue;
    positional.push(arg);
  }
  const result: { name?: string; dir?: string } = {};
  const name = positional[0];
  const dir = positional[1];
  if (name) result.name = name;
  if (dir) result.dir = dir;
  return result;
}

async function prompt(question: string): Promise<string> {
  const rl = createInterface({ input: stdin, output: stdout });
  const answer = await rl.question(question);
  rl.close();
  return answer.trim();
}

async function main(): Promise<void> {
  const { name: argName, dir: argDir } = parseArgs(process.argv);

  const name = argName ?? (await prompt("Script project name (e.g. my-counter): "));
  if (!name) throw new Error("A project name is required.");
  assertValidName(name);

  const defaultDir = resolve(process.cwd(), name);
  const dir = argDir ?? defaultDir;

  const result = scaffoldProject(dir, name);

  stdout.write(`\nCreated ${result.files.length} files in ${result.dir}\n`);
  for (const file of result.files) stdout.write(`  ${file}\n`);
  stdout.write(`\nNext steps:\n  cd ${name}\n  npm install\n  npm test\n`);
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`Error: ${message}\n`);
  process.exit(1);
});
