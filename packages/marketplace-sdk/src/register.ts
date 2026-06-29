import type { Init, Update, View, State } from "./types.js";

interface GlobalLifecycle {
  init?: Init;
  view?: View;
  update?: Update;
}

function lifecycle(): GlobalLifecycle {
  return globalThis as unknown as GlobalLifecycle;
}

export function register<S extends State = State>(
  initFn: Init<S>,
  viewFn: View<S>,
  updateFn: Update<S>,
): void {
  assertFunction(initFn, "init");
  assertFunction(viewFn, "view");
  assertFunction(updateFn, "update");
  const g = lifecycle();
  g.init = initFn as unknown as Init;
  g.view = viewFn as unknown as View;
  g.update = updateFn as unknown as Update;
}

function assertFunction(value: unknown, name: string): void {
  if (typeof value !== "function") {
    throw new Error(`register(): "${name}" must be a function (got ${describe(value)})`);
  }
}

function describe(value: unknown): string {
  if (value === null) return "null";
  if (value === undefined) return "undefined";
  return typeof value;
}

export function getInit(): Init {
  const fn = lifecycle().init;
  if (typeof fn !== "function") {
    throw new Error("register() was not called: global init is missing");
  }
  return fn;
}

export function getView(): View {
  const fn = lifecycle().view;
  if (typeof fn !== "function") {
    throw new Error("register() was not called: global view is missing");
  }
  return fn;
}

export function getUpdate(): Update {
  const fn = lifecycle().update;
  if (typeof fn !== "function") {
    throw new Error("register() was not called: global update is missing");
  }
  return fn;
}
