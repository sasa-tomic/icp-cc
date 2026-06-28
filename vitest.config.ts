import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["packages/*/src/__tests__/**/*.test.ts"],
    testTimeout: 120000,
    hookTimeout: 120000,
  },
});
