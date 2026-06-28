import { newQuickJSWASMModuleFromVariant } from "quickjs-emscripten";
import variant from "@jitl/quickjs-singlefile-browser-release-sync";

export interface QuickJSEvalOptions {
  bootstrap?: string;
  bundleSource: string;
  initArg?: unknown;
  updateMsg?: unknown;
}

export interface QuickJSEvalResult {
  lifecycleTypes: string[];
  initResult: unknown;
  viewResult: unknown;
  updateResult: unknown;
  raw: {
    init: string;
    view: string;
    update: string;
    types: string;
  };
}

let cachedModule: Awaited<ReturnType<typeof newQuickJSWASMModuleFromVariant>> | null = null;

async function getModule() {
  if (!cachedModule) cachedModule = await newQuickJSWASMModuleFromVariant(variant);
  return cachedModule;
}

export async function evalBundleInQuickJS(
  options: QuickJSEvalOptions,
): Promise<QuickJSEvalResult> {
  const QuickJS = await getModule();
  const ctx = QuickJS.newContext();
  try {
    const run = async (code: string): Promise<string> => {
      const result = await ctx.evalCode(code, "harness.js");
      if ("error" in result && result.error) {
        const err = ctx.dump(result.error);
        result.error.dispose();
        throw new Error(`QuickJS eval error: ${JSON.stringify(err)}`);
      }
      const value = result.value;
      if (!value) throw new Error("QuickJS eval returned no value");
      const out = ctx.getString(value);
      value.dispose();
      return out;
    };

    if (options.bootstrap) await run(options.bootstrap);
    await run(options.bundleSource);

    const typesJson = await run(`JSON.stringify([typeof init, typeof view, typeof update])`);
    const types = JSON.parse(typesJson) as string[];
    const initJson = await run(`JSON.stringify(init(${JSON.stringify(options.initArg ?? {})}))`);
    const initResult = JSON.parse(initJson);
    const state = (initResult as { state?: unknown }).state ?? {};
    const viewJson = await run(`JSON.stringify(view(${JSON.stringify(state)}))`);
    const viewResult = JSON.parse(viewJson);
    const msg = options.updateMsg ?? { type: "__noop__" };
    const updateJson = await run(
      `JSON.stringify(update(${JSON.stringify(msg)}, ${JSON.stringify(state)}))`,
    );
    const updateResult = JSON.parse(updateJson);

    return {
      lifecycleTypes: types,
      initResult,
      viewResult,
      updateResult,
      raw: { init: initJson, view: viewJson, update: updateJson, types: typesJson },
    };
  } finally {
    ctx.dispose();
  }
}
