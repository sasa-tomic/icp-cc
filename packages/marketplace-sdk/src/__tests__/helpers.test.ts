import { describe, it, expect } from "vitest";
import { canonical } from "./canonical.js";
import {
  icpCall,
  icpBatch,
  icpMessage,
  icpUiList,
  icpResultDisplay,
  icpSearchableList,
  icpSection,
  icpTable,
  icpFilterItems,
  icpSortItems,
  icpGroupBy,
} from "../helpers.js";

describe("icp_* helpers — byte-identical to Rust oracle", () => {
  it("icp_call: sets action=call and passes through spec fields", () => {
    const out = icpCall({
      canister: "rrkah-fqaaa-aaaaa-aaaaq-cai",
      method: "get_balance",
      args: "()",
    });
    expect(canonical(out)).toBe(
      '{"action":"call","args":"()","canister":"rrkah-fqaaa-aaaaa-aaaaq-cai","method":"get_balance"}',
    );
  });

  it("icp_call: defaults to empty object when spec omitted", () => {
    const out = icpCall(undefined as never);
    expect(canonical(out)).toBe('{"action":"call"}');
  });

  it("icp_batch: wraps array of calls", () => {
    const out = icpBatch([
      { canister: "rrkah-fqaaa-aaaaa-aaaaq-cai", method: "get_balance", args: "()" },
      { canister: "ryjl3-tyaaa-aaaaa-aaaba-cai", method: "get_account_id", args: "()" },
    ]);
    expect(canonical(out)).toBe(
      '{"action":"batch","calls":[{"args":"()","canister":"rrkah-fqaaa-aaaaa-aaaaq-cai","method":"get_balance"},{"args":"()","canister":"ryjl3-tyaaa-aaaaa-aaaba-cai","method":"get_account_id"}]}',
    );
  });

  it("icp_batch: defaults to empty array when calls omitted", () => {
    expect(canonical(icpBatch(undefined))).toBe('{"action":"batch","calls":[]}');
  });

  it("icp_message: coerces text and type, defaults to info", () => {
    expect(canonical(icpMessage({ text: "Hello, World!", type: "info" }))).toBe(
      '{"action":"message","text":"Hello, World!","type":"info"}',
    );
    expect(canonical(icpMessage(undefined))).toBe(
      '{"action":"message","text":"","type":"info"}',
    );
  });

  it("icp_ui_list: items + buttons, ignores title (parity quirk)", () => {
    const out = icpUiList({
      items: ["Item 1", "Item 2", "Item 3"],
      title: "Simple List",
    });
    expect(canonical(out)).toBe(
      '{"action":"ui","ui":{"buttons":[],"items":["Item 1","Item 2","Item 3"],"type":"list"}}',
    );
  });

  it("icp_ui_list: defaults to empty items/buttons", () => {
    expect(canonical(icpUiList(undefined))).toBe(
      '{"action":"ui","ui":{"buttons":[],"items":[],"type":"list"}}',
    );
  });

  it("icp_result_display: passes spec as props", () => {
    const out = icpResultDisplay({ result: "Success: Operation completed", type: "success" });
    expect(canonical(out)).toBe(
      '{"action":"ui","ui":{"props":{"result":"Success: Operation completed","type":"success"},"type":"result_display"}}',
    );
  });

  it("icp_searchable_list: props.searchable defaults true unless explicitly false", () => {
    const out = icpSearchableList({
      items: [
        { id: 1, name: "Transaction 1", amount: "100" },
        { id: 2, name: "Transaction 2", amount: "200" },
      ],
      title: "Recent Transactions",
      searchable: true,
    });
    expect(canonical(out)).toBe(
      '{"action":"ui","ui":{"props":{"items":[{"amount":"100","id":1,"name":"Transaction 1"},{"amount":"200","id":2,"name":"Transaction 2"}],"searchable":true,"title":"Recent Transactions"},"type":"list"}}',
    );
  });

  it("icp_searchable_list: searchable:false disables", () => {
    const out = icpSearchableList({ searchable: false });
    expect(canonical(out)).toBe(
      '{"action":"ui","ui":{"props":{"items":[],"searchable":false,"title":"Results"},"type":"list"}}',
    );
  });

  it("icp_section: title + content defaults to empty", () => {
    const out = icpSection({ title: "Section Title", content: "This is the section content" });
    expect(canonical(out)).toBe(
      '{"action":"ui","ui":{"props":{"content":"This is the section content","title":"Section Title"},"type":"section"}}',
    );
    expect(canonical(icpSection(undefined))).toBe(
      '{"action":"ui","ui":{"props":{"content":"","title":""},"type":"section"}}',
    );
  });

  it("icp_table: passes data as props", () => {
    const out = icpTable({
      data: [
        { name: "Alice", age: 30, city: "New York" },
        { name: "Bob", age: 25, city: "London" },
      ],
      headers: ["Name", "Age", "City"],
    });
    expect(canonical(out)).toBe(
      '{"action":"ui","ui":{"props":{"data":[{"age":30,"city":"New York","name":"Alice"},{"age":25,"city":"London","name":"Bob"}],"headers":["Name","Age","City"]},"type":"table"}}',
    );
  });

  it("icp_filter_items: substring match on field", () => {
    const out = icpFilterItems(
      [
        { name: "Alice", city: "New York" },
        { name: "Bob", city: "London" },
        { name: "Charlie", city: "New York" },
      ],
      "city",
      "New York",
    );
    expect(canonical(out)).toBe(
      '[{"city":"New York","name":"Alice"},{"city":"New York","name":"Charlie"}]',
    );
  });

  it("icp_sort_items: ascending by stringified field", () => {
    const out = icpSortItems(
      [
        { name: "Charlie", age: 30 },
        { name: "Alice", age: 25 },
        { name: "Bob", age: 35 },
      ],
      "name",
      true,
    );
    expect(canonical(out)).toBe(
      '[{"age":25,"name":"Alice"},{"age":35,"name":"Bob"},{"age":30,"name":"Charlie"}]',
    );
  });

  it("icp_sort_items: descending by stringified field", () => {
    const out = icpSortItems(
      [
        { name: "Alice", age: 25 },
        { name: "Charlie", age: 30 },
      ],
      "name",
      false,
    );
    expect(canonical(out)).toBe(
      '[{"age":30,"name":"Charlie"},{"age":25,"name":"Alice"}]',
    );
  });

  it("icp_group_by: groups items by stringified field", () => {
    const out = icpGroupBy(
      [
        { name: "Alice", city: "New York" },
        { name: "Bob", city: "London" },
        { name: "Charlie", city: "New York" },
        { name: "Diana", city: "London" },
      ],
      "city",
    );
    expect(canonical(out)).toBe(
      '{"London":[{"city":"London","name":"Bob"},{"city":"London","name":"Diana"}],"New York":[{"city":"New York","name":"Alice"},{"city":"New York","name":"Charlie"}]}',
    );
  });

  it("icp_group_by: missing field groups under 'unknown'", () => {
    const out = icpGroupBy([{ name: "Alice" }, { name: "Bob", city: "London" }], "city");
    expect(canonical(out)).toBe(
      '{"London":[{"city":"London","name":"Bob"}],"unknown":[{"name":"Alice"}]}',
    );
  });
});
