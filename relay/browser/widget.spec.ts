import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test, type Page, type Route } from "@playwright/test";

/**
 * The web widget against a stubbed board route. The page and its files are served from
 * widget/ at a fake relay origin; avatars never load (GitHub is blocked), so rows show initials.
 *
 * Set WIDGET_SCREENS=<dir> to also save a screenshot of each state there.
 */

const ORIGIN = "https://relay.test";
const INSTALLATION = "inst-widget-0001";
const TOKEN = "a1".repeat(32);
const WIDGET_URL = `${ORIGIN}/v1/widget?layout=standby#installation=${INSTALLATION}&token=${TOKEN}`;
const WIDGET_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "widget");
const T0 = new Date("2026-11-10T18:00:00Z");
const NOW = T0.getTime() / 1000;
const SCREENS = process.env.WIDGET_SCREENS;

const FILES: Record<string, [string, string]> = {
  "/v1/widget": ["standby.html", "text/html; charset=utf-8"],
  "/v1/widget/standby.css": ["standby.css", "text/css; charset=utf-8"],
  "/v1/widget/standby.js": ["standby.js", "text/javascript; charset=utf-8"],
  "/v1/widget/fonts/InterTight-Regular.ttf": ["fonts/InterTight-Regular.ttf", "font/ttf"],
  "/v1/widget/fonts/InterTight-ExtraBold.ttf": ["fonts/InterTight-ExtraBold.ttf", "font/ttf"],
};

interface Row {
  rank: number;
  login: string;
  contributions: number | null;
  movementToday: number;
  isSelf: boolean;
}

/** A board-route body like the README's: you third, as in the StandBy screenshots. */
function board(overrides: Record<string, unknown> = {}, rows?: Row[]) {
  const list: Row[] = rows ?? [
    { rank: 1, login: "jordan", contributions: 21, movementToday: 0, isSelf: false },
    { rank: 2, login: "alex", contributions: 15, movementToday: 1, isSelf: false },
    { rank: 3, login: "addisonk", contributions: 12, movementToday: 1, isSelf: true },
    { rank: 4, login: "samantha-rivera-de-la-cruz-montgomery", contributions: 9, movementToday: -2, isSelf: false },
    { rank: 5, login: "taylor", contributions: 4, movementToday: 0, isSelf: false },
  ];
  return {
    window: "daily",
    login: "addisonk",
    rank: 3,
    competitorCount: list.length,
    contributions: 12,
    above: { login: "alex", contributions: 15, movementToday: 1 },
    below: { login: "samantha-rivera-de-la-cruz-montgomery", contributions: 9, movementToday: -2 },
    movementToday: 1,
    gapToPass: 3,
    updatedAt: NOW - 90,
    rows: list,
    ...overrides,
  };
}

type Reply = { status: number; body: unknown } | "hang";

interface Harness {
  requests: { url: string; authorization: string | null }[];
  reply: (next: Reply) => void;
}

async function open(page: Page, first: Reply, url = WIDGET_URL): Promise<Harness> {
  const harness: Harness = { requests: [], reply: () => {} };
  let current = first;
  harness.reply = (next) => {
    current = next;
  };
  page.on("request", (request) => {
    harness.requests.push({ url: request.url(), authorization: request.headers()["authorization"] ?? null });
  });
  await page.clock.install({ time: T0 });
  await page.route(/^https:\/\/(github\.com|avatars\.githubusercontent\.com)\//, (route) => route.abort());
  await page.route(`${ORIGIN}/**`, async (route: Route) => {
    const { pathname } = new URL(route.request().url());
    const file = FILES[pathname];
    if (file) {
      return route.fulfill({ status: 200, contentType: file[1], body: readFileSync(path.join(WIDGET_DIR, file[0])) });
    }
    if (/^\/v1\/installations\/[^/]+\/board$/.test(pathname)) {
      const reply = current;
      if (reply === "hang") return; // never answered: the first load
      return route.fulfill({ status: reply.status, contentType: "application/json", body: JSON.stringify(reply.body) });
    }
    return route.fulfill({ status: 404, body: "" });
  });
  await page.goto(url);
  return harness;
}

async function screenshot(page: Page, name: string) {
  if (SCREENS) await page.screenshot({ path: path.join(SCREENS, `${name}.png`) });
}

const rank = (page: Page) => page.getByTestId("rank");
const count = (page: Page) => page.getByTestId("count");
const status = (page: Page) => page.getByTestId("status");
const rows = (page: Page) => page.getByTestId("row");

test("first load shows placeholders, never zero", async ({ page }) => {
  await open(page, "hang");
  await expect(rank(page)).toHaveText("–");
  await expect(count(page)).toHaveText("–");
  await expect(page.locator("body")).not.toContainText("0");
  await screenshot(page, "first-load");
});

test("renders the StandBy pair from the board route", async ({ page }) => {
  const harness = await open(page, { status: 200, body: board() });
  await expect(rank(page)).toHaveText("#3");
  await expect(count(page)).toHaveText("12");
  await expect(status(page)).toHaveText("3 to pass alex");
  await expect(page.getByText("Today").first()).toBeVisible();
  await expect(rows(page)).toHaveCount(5);
  await expect(rows(page).nth(0)).toContainText("#1");
  await expect(rows(page).nth(0)).toContainText("jordan");
  await expect(rows(page).nth(0)).toContainText("21");
  await expect(rows(page).nth(0)).toContainText("JO"); // initials: GitHub is unreachable here
  const me = rows(page).nth(2);
  await expect(me).toContainText("addisonk");
  await expect(me).toContainText("you");
  await expect(me).toHaveAttribute("data-self", "true");
  await expect(me.getByTestId("movement")).toHaveAttribute("data-direction", "up");
  await expect(rows(page).nth(3).getByTestId("movement")).toHaveAttribute("data-direction", "down");
  await expect(rows(page).nth(0).getByTestId("movement")).toHaveCount(0);
  // Long logins truncate in the middle, as the app's rows do.
  await expect(rows(page).nth(3)).toContainText("…");
  await expect(page.locator("html")).not.toHaveAttribute("data-state", "stale");
  await screenshot(page, "normal");

  const boardCalls = harness.requests.filter((r) => r.url.includes("/board"));
  expect(boardCalls.length).toBe(1);
  expect(boardCalls[0]!.url).toBe(`${ORIGIN}/v1/installations/${INSTALLATION}/board?window=daily`);
  expect(boardCalls[0]!.authorization).toBe(`Bearer ${TOKEN}`);
  for (const request of harness.requests) expect(request.url).not.toContain(TOKEN);
});

test("polls every 5 minutes, keeps the board on a failed refresh, then turns stale after 20 minutes", async ({ page }) => {
  const harness = await open(page, { status: 200, body: board() });
  await expect(count(page)).toHaveText("12");

  harness.reply({ status: 503, body: { error: "unavailable", message: "x" } });
  await page.clock.runFor(5 * 60_000);
  await expect.poll(() => harness.requests.filter((r) => r.url.includes("/board")).length).toBe(2);
  await expect(count(page)).toHaveText("12");
  await expect(rows(page)).toHaveCount(5);
  await expect(page.locator("html")).not.toHaveAttribute("data-state", "stale");

  // updatedAt was 90 s before T0: past 20 minutes of data age it's stale.
  await page.clock.runFor(14 * 60_000);
  await expect(page.locator("html")).toHaveAttribute("data-state", "stale");
  await expect(count(page)).toHaveText("12");
  await expect(page.getByTestId("age")).toContainText("20 min");
  await screenshot(page, "stale");

  // A good refresh clears it.
  harness.reply({ status: 200, body: board({ updatedAt: NOW + 19 * 60 }) });
  await page.clock.runFor(5 * 60_000);
  await expect(page.locator("html")).not.toHaveAttribute("data-state", "stale");
});

test("stale data on first load renders stale", async ({ page }) => {
  await open(page, { status: 200, body: board({ updatedAt: NOW - 45 * 60 }) });
  await expect(page.locator("html")).toHaveAttribute("data-state", "stale");
  await expect(rank(page)).toHaveText("#3");
});

for (const [code, error] of [
  [401, "unauthorized"],
  [403, "revoked"],
] as const) {
  test(`${code} says this screen's access was revoked`, async ({ page }) => {
    await open(page, { status: code, body: { error, message: "x" } });
    await expect(page.getByText("This screen's access was revoked")).toBeVisible();
    await expect(page.locator("html")).toHaveAttribute("data-state", "revoked");
    if (code === 403) await screenshot(page, "revoked");
  });
}

test("a revocation replaces a board already on screen", async ({ page }) => {
  const harness = await open(page, { status: 200, body: board() });
  await expect(rows(page)).toHaveCount(5);
  harness.reply({ status: 403, body: { error: "revoked", message: "x" } });
  await page.clock.runFor(5 * 60_000);
  await expect(page.getByText("This screen's access was revoked")).toBeVisible();
  await expect(rows(page)).toHaveCount(0);
});

test("404 says Live rank is off on your iPhone", async ({ page }) => {
  await open(page, { status: 404, body: { error: "not_found", message: "x" } });
  await expect(page.getByText("Live rank is off on your iPhone")).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("data-state", "gone");
  await screenshot(page, "installation-gone");
});

test("no rivals shows your count without a rank", async ({ page }) => {
  await open(page, {
    status: 200,
    body: board(
      { rank: null, competitorCount: 1, contributions: 7, above: null, below: null, gapToPass: null, movementToday: 0 },
      [{ rank: 1, login: "addisonk", contributions: 7, movementToday: 0, isSelf: true }],
    ),
  });
  await expect(count(page)).toHaveText("7");
  await expect(rank(page)).toBeHidden();
  await expect(status(page)).toHaveText("Just you so far");
  await expect(page.locator("body")).not.toContainText("#1 of 1");
  await screenshot(page, "no-rivals");
});

test("first place has nobody to pass", async ({ page }) => {
  await open(page, {
    status: 200,
    body: board({ rank: 1, contributions: 30, above: null, gapToPass: null }, [
      { rank: 1, login: "addisonk", contributions: 30, movementToday: 0, isSelf: true },
      { rank: 2, login: "jordan", contributions: 21, movementToday: 0, isSelf: false },
    ]),
  });
  await expect(rank(page)).toHaveText("#1");
  await expect(page.locator("body")).not.toContainText("to pass");
});

test("a missing fragment says how to set the page up, without calling the relay", async ({ page }) => {
  const harness = await open(page, { status: 200, body: board() }, `${ORIGIN}/v1/widget`);
  await expect(page.getByText("installation=")).toBeVisible();
  expect(harness.requests.filter((r) => r.url.includes("/board"))).toHaveLength(0);
});

test("a rank change ticks the count up and swaps rows with transforms", async ({ page }) => {
  const harness = await open(page, { status: 200, body: board() });
  await expect(rows(page).nth(1)).toContainText("alex");

  harness.reply({
    status: 200,
    body: board({ rank: 2, contributions: 16, above: { login: "jordan", contributions: 21, movementToday: 0 }, gapToPass: 5, movementToday: 2, updatedAt: NOW + 290 }, [
      { rank: 1, login: "jordan", contributions: 21, movementToday: 0, isSelf: false },
      { rank: 2, login: "addisonk", contributions: 16, movementToday: 2, isSelf: true },
      { rank: 3, login: "alex", contributions: 15, movementToday: 0, isSelf: false },
      { rank: 4, login: "samantha-rivera-de-la-cruz-montgomery", contributions: 9, movementToday: -2, isSelf: false },
      { rank: 5, login: "taylor", contributions: 4, movementToday: 0, isSelf: false },
    ]),
  });
  // Record what moves during the update: only transform/opacity transitions, on the swapped rows.
  await page.evaluate(() => {
    const seen: string[] = [];
    (window as unknown as { __seen: string[] }).__seen = seen;
    document.addEventListener("transitionrun", (event) => seen.push((event as TransitionEvent).propertyName), true);
  });
  await page.clock.runFor(5 * 60_000);
  await expect(rank(page)).toHaveText("#2");
  await expect(rows(page).nth(1)).toContainText("addisonk");
  await expect(rows(page).nth(2)).toContainText("alex");
  await expect(status(page)).toHaveText("5 to pass jordan");
  await page.clock.runFor(2_000);
  await expect(count(page)).toHaveText("16");
  await expect(rows(page).nth(1).getByTestId("movement")).toHaveAttribute("data-direction", "up");
  const seen = await page.evaluate(() => (window as unknown as { __seen: string[] }).__seen);
  expect(seen).toContain("transform");
  for (const property of seen) expect(["transform", "opacity"]).toContain(property);
});

for (const [name, width, height] of [
  ["tile", 1280, 1080],
  ["standby", 852, 393],
  ["small", 360, 240],
  ["tall", 400, 900],
] as const) {
  test(`fills a ${width}×${height} box without overflowing`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    const many: Row[] = Array.from({ length: 14 }, (_, i) => ({
      rank: i + 1,
      login: i === 9 ? "addisonk" : `rival-number-${i + 1}`,
      contributions: 40 - i * 2,
      movementToday: i % 3 === 0 ? 1 : 0,
      isSelf: i === 9,
    }));
    await open(page, { status: 200, body: board({ rank: 10, contributions: 22, above: { login: "rival-number-9", contributions: 24, movementToday: 0 }, gapToPass: 2 }, many) });
    await expect(rank(page)).toHaveText("#10");
    const overflow = await page.evaluate(() => {
      const root = document.documentElement;
      const bad: string[] = [];
      document.querySelectorAll("body *").forEach((el) => {
        const r = el.getBoundingClientRect();
        if (r.width === 0 && r.height === 0) return;
        if (r.left < -0.5 || r.top < -0.5 || r.right > innerWidth + 0.5 || r.bottom > innerHeight + 0.5) {
          bad.push(`${el.tagName}.${(el as HTMLElement).className} ${Math.round(r.left)},${Math.round(r.top)},${Math.round(r.right)},${Math.round(r.bottom)}`);
        }
      });
      return { scrollW: root.scrollWidth, scrollH: root.scrollHeight, bad };
    });
    expect(overflow.bad).toEqual([]);
    expect(overflow.scrollW).toBeLessThanOrEqual(width);
    expect(overflow.scrollH).toBeLessThanOrEqual(height);
    // Your race is always on screen: you, and the person you're chasing.
    await expect(page.locator('[data-testid="row"][data-self="true"]')).toBeVisible();
    await expect(rows(page).filter({ hasText: "#9" })).toBeVisible();
    // A tall box shows more of the board than a short one.
    const shown = await rows(page).count();
    if (name === "tile") expect(shown).toBeGreaterThanOrEqual(8);
    expect(shown).toBeGreaterThanOrEqual(2);
    await screenshot(page, `fill-${name}-${width}x${height}`);
  });
}
