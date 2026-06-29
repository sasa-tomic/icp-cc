import { describe, it, expect, afterEach } from "vitest";
import { register, getInit, getView, getUpdate } from "../register.js";

describe("register()", () => {
  afterEach(() => {
    delete (globalThis as Record<string, unknown>).init;
    delete (globalThis as Record<string, unknown>).view;
    delete (globalThis as Record<string, unknown>).update;
  });

  it("assigns init/view/update as globals so the host can discover them", () => {
    const init = () => ({ state: { count: 0 }, effects: [] });
    const view = () => ({ type: "text", props: { text: "0" } });
    const update = () => ({ state: { count: 1 }, effects: [] });

    register(init, view, update);

    expect(typeof globalThis.init).toBe("function");
    expect(typeof globalThis.view).toBe("function");
    expect(typeof globalThis.update).toBe("function");
    expect(getInit()).toBe(init);
    expect(getView()).toBe(view);
    expect(getUpdate()).toBe(update);
  });

  it("getInit throws fast when register() was not called", () => {
    expect(() => getInit()).toThrow(/register\(\) was not called/);
  });

  it("throws fast when any argument is not a function (G14 host contract parity)", () => {
    const init = () => ({ state: { count: 0 }, effects: [] });
    const view = () => ({ type: "text", props: { text: "0" } });
    const update = () => ({ state: { count: 1 }, effects: [] });
    expect(() => register(null as never, view, update)).toThrow(/init.*function/i);
    expect(() => register(init, "nope" as never, update)).toThrow(/view.*function/i);
    expect(() => register(init, view, {} as never)).toThrow(/update.*function/i);
  });
});
