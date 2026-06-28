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
  const g = lifecycle();
  g.init = initFn as unknown as Init;
  g.view = viewFn as unknown as View;
  g.update = updateFn as unknown as Update;
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
