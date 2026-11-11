import path from "node:path";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest(async () => {
      const migrations = await readD1Migrations(path.join(__dirname, "migrations"));
      return {
        wrangler: { configPath: "./wrangler.jsonc" },
        miniflare: {
          // Test-only bindings: the D1 migrations, and a dummy APNs config so the real
          // sender can be constructed. Tests never reach Apple; they inject a fake APNs.
          bindings: {
            TEST_MIGRATIONS: migrations,
            APNS_KEY_ID: "TESTKEY123",
            APNS_TEAM_ID: "TESTTEAM12",
            APNS_PRIVATE_KEY: "",
          },
        },
      };
    }),
  ],
  test: {
    // browser/ holds the Playwright specs (`npm run test:browser`).
    include: ["test/**/*.test.ts"],
    setupFiles: ["./test/apply-migrations.ts"],
  },
});
