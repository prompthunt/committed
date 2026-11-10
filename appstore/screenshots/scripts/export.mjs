// Exports the iPhone deck from a running editor (`bun dev`) with headless Chromium, the same as
// pressing Export bundle, and unzips the PNGs into an output folder.
//
//   node scripts/export.mjs [http://localhost:3000] [out-dir]
import { chromium } from "playwright";
import JSZip from "jszip";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const url = process.argv[2] ?? "http://localhost:3000";
const out = path.resolve(process.argv[3] ?? "export");

const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1800, height: 1000 }, acceptDownloads: true });
  await page.goto(url, { waitUntil: "networkidle" });
  await page.getByRole("button", { name: "Export bundle", exact: true }).waitFor();
  await page.waitForTimeout(1500); // fonts and screenshots
  const [download] = await Promise.all([
    page.waitForEvent("download", { timeout: 200_000 }),
    page.getByRole("button", { name: "Export bundle", exact: true }).click(),
  ]);
  const zip = await JSZip.loadAsync(await readFile(await download.path()));
  await mkdir(out, { recursive: true });
  for (const [name, entry] of Object.entries(zip.files)) {
    if (entry.dir || !name.endsWith(".png")) continue;
    const file = path.join(out, name);
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, await entry.async("nodebuffer"));
    console.log(name);
  }
} finally {
  await browser.close();
}
