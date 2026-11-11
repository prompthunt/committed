import { defineConfig, devices } from "@playwright/test";

// Browser tests of the web widget (widget/) against a stubbed board route. No relay runs: the
// spec serves widget/ from disk at a fake origin and answers the board route itself.
export default defineConfig({
  testDir: "./browser",
  timeout: 30_000,
  fullyParallel: true,
  reporter: [["list"]],
  use: { ...devices["Desktop Chrome"], viewport: { width: 1280, height: 1080 } },
});
