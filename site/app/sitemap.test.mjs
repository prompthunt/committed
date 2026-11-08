import assert from "node:assert/strict";
import { test } from "node:test";
import sitemap from "./sitemap.ts";

test("the sitemap lists the home, privacy and support pages", () => {
  assert.deepEqual(
    sitemap().map(({ url }) => url),
    ["https://gitcommitted.app", "https://gitcommitted.app/privacy", "https://gitcommitted.app/support"],
  );
});
