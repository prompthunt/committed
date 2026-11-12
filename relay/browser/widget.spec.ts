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
const WIDGET_URL = `${ORIGIN}/v1/widget?size=medium#installation=${INSTALLATION}&token=${TOKEN}`;
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
  "/v1/widget/fonts/JetBrainsMono-Medium.ttf": ["fonts/JetBrainsMono-Medium.ttf", "font/ttf"],
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
    displayName: "Addison Kowalski",
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

async function open(page: Page, first: Reply, url = WIDGET_URL, html?: string, avatar?: Buffer): Promise<Harness> {
  const harness: Harness = { requests: [], reply: () => {} };
  let current = first;
  harness.reply = (next) => {
    current = next;
  };
  page.on("request", (request) => {
    harness.requests.push({ url: request.url(), authorization: request.headers()["authorization"] ?? null });
  });
  await page.clock.install({ time: T0 });
  await page.route(/^https:\/\/(github\.com|avatars\.githubusercontent\.com)\//, (route) =>
    avatar ? route.fulfill({ status: 200, contentType: "image/png", body: avatar }) : route.abort()
  );
  await page.route(`${ORIGIN}/**`, async (route: Route) => {
    const { pathname } = new URL(route.request().url());
    if (pathname === "/v1/widget" && html !== undefined) {
      return route.fulfill({ status: 200, contentType: "text/html; charset=utf-8", body: html });
    }
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
const card = (page: Page) => page.getByTestId("card");
const selfRow = (page: Page) => page.locator('[data-testid="row"][data-self="true"]');
const LIME = "rgb(200, 255, 46)";
const LIME_DEEP = "rgb(139, 196, 26)";
const SOFT = "rgb(214, 217, 208)";
const MUTED = "rgb(142, 146, 136)";
/** Apple's vibrant tokens (dark), as plain alpha white: what the page draws with when framed. */
const LABEL_SECONDARY = "rgba(255, 255, 255, 0.6)";
const SEPARATOR = "rgba(255, 255, 255, 0.1)";
const color = (locator: ReturnType<Page["locator"]>) => locator.evaluate((el) => getComputedStyle(el).color);
/** The classes on the page's <html>, sorted; layout classes such as "stacked" aren't at 1280×1080. */
const htmlClasses = (frame: { evaluate: Page["evaluate"] }) =>
  frame.evaluate(() => document.documentElement.className.split(/\s+/).filter(Boolean).sort());

test("first load shows placeholders, never zero", async ({ page }) => {
  await open(page, "hang");
  await expect(rank(page)).toHaveText("–");
  await expect(status(page)).toHaveText("Your board is loading");
  await expect(page.getByTestId("rank-of")).toBeHidden();
  // Never a fake zero (the folio's "01" is a label, not a count).
  await expect(page.locator("body")).not.toContainText(/\b0\b/);
  await screenshot(page, "first-load");
});

test("renders the StandBy pair from the board route", async ({ page }) => {
  const harness = await open(page, { status: 200, body: board() });
  await expect(rank(page)).toHaveText("#3");
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

test("the hero card: folio, who you are, your rank of N, then today's news and the age", async ({ page }) => {
  await open(page, { status: 200, body: board() });
  const hero = card(page);
  await expect(hero.getByTestId("folio")).toHaveText(/^01 · today$/i);
  await expect(hero.getByTestId("folio-label")).toHaveText(/^your rank$/i);
  await expect(hero.getByTestId("who-name")).toHaveText("Addison"); // the first name, as the app shows it
  await expect(hero.getByTestId("who-handle")).toHaveText("@addisonk");
  await expect(hero.getByTestId("who-avatar")).toContainText("AD");
  await expect(rank(page)).toHaveText("#3");
  await expect(hero.getByTestId("rank-of")).toHaveText("of 5");
  await expect(hero.getByTestId("movement-line")).toHaveText("Up 1 today");
  expect(await color(hero.getByTestId("movement-line"))).toBe(LIME);
  await expect(status(page)).toHaveText("3 to pass alex");
  expect(await color(status(page))).toBe(LIME);
  await expect(page.getByTestId("age")).toHaveText("Updated 1 min ago");
  expect(await color(page.getByTestId("age"))).toBe(SOFT);
  // Rank only: your count stays on your row, not on the card.
  await expect(hero).not.toContainText("12");
  await expect(count(page)).toBeHidden();
  // The order down the card: folio, identity, rank, then the news.
  const top = async (id: string) => (await hero.getByTestId(id).boundingBox())!.y;
  expect(await top("folio")).toBeLessThan(await top("who-name"));
  expect(await top("who-name")).toBeLessThan(await top("rank"));
  expect(await top("rank")).toBeLessThan(await top("movement-line"));
  expect(await top("movement-line")).toBeLessThan(await top("status"));
  expect(await top("status")).toBeLessThan(await top("age"));
  // The card sits on its own tile: Committed's tile color with a hairline, left of the board.
  const style = await hero.evaluate((el) => {
    const s = getComputedStyle(el);
    return { bg: s.backgroundColor, border: s.borderTopColor, radius: parseFloat(s.borderTopLeftRadius) };
  });
  expect(style.bg).toBe("rgb(14, 16, 11)");
  expect(style.border).toBe("rgba(255, 255, 255, 0.07)");
  expect(style.radius).toBeGreaterThan(8);
  expect((await hero.boundingBox())!.x).toBeLessThan((await rows(page).first().boundingBox())!.x);
  // The board's header is just the eyebrow: no trophy, no age.
  await expect(page.getByTestId("list-head")).toHaveText(/^5 people · today$/i);
  expect(await color(page.getByTestId("list-head"))).toBe(MUTED);
  await expect(page.getByTestId("board")).not.toContainText("Updated");
  await expect(page.getByTestId("board").locator("svg.trophy")).toHaveCount(0);
});

test("the eyebrows are set in the relay's monospace, uppercase", async ({ page }) => {
  await open(page, { status: 200, body: board() });
  await expect(rank(page)).toHaveText("#3");
  const font = await page.evaluate(async () => {
    await document.fonts.ready;
    const faces: string[] = [];
    document.fonts.forEach((face) => {
      if (face.status === "loaded") faces.push(`${face.family.replace(/"/g, "")} ${face.weight}`);
    });
    const folio = getComputedStyle(document.querySelector('[data-testid="folio"]')!);
    return { faces, family: folio.fontFamily, transform: folio.textTransform };
  });
  expect(font.faces).toContain("JetBrains Mono 500");
  expect(font.family).toMatch(/^"?JetBrains Mono/);
  expect(font.transform).toBe("uppercase");
});

test("movement: down in soft, nothing when you held your place", async ({ page }) => {
  const harness = await open(page, { status: 200, body: board({ movementToday: -2 }) });
  const line = page.getByTestId("movement-line");
  await expect(line).toHaveText("Down 2 today");
  expect(await color(line)).toBe(SOFT);
  harness.reply({ status: 200, body: board({ movementToday: 0, updatedAt: NOW + 200 }) });
  await page.clock.runFor(5 * 60_000);
  await expect(line).toBeHidden();
  await expect(status(page)).toHaveText("3 to pass alex");
});

test("the age reads as the app's: just now, then minutes, then hours", async ({ page }) => {
  await open(page, { status: 200, body: board({ updatedAt: NOW - 20 }) });
  const age = page.getByTestId("age");
  await expect(age).toHaveText("Updated just now");
  await page.clock.runFor(6 * 60_000);
  await expect(age).toHaveText("Updated 6 min ago");
  await page.clock.runFor(2 * 60 * 60_000);
  await expect(age).toHaveText("Updated 2 hr ago");
});

test("without a public name the card shows your @login alone", async ({ page }) => {
  await open(page, { status: 200, body: board({ displayName: null }) });
  await expect(card(page).getByTestId("who-name")).toHaveText("@addisonk");
  await expect(card(page).getByTestId("who-handle")).toBeHidden();
});

for (const [windowName, number, title] of [
  ["weekly", "02", "7 days"],
  ["monthly", "03", "30 days"],
] as const) {
  test(`the ${windowName} window titles the folio and the list as the app does (${title})`, async ({ page }) => {
    const harness = await open(
      page,
      { status: 200, body: board({ window: windowName, movementToday: 0 }) },
      `${WIDGET_URL}&window=${windowName}`,
    );
    await expect(card(page).getByTestId("folio")).toHaveText(new RegExp(`^${number} · ${title}$`, "i"));
    await expect(page.getByTestId("list-head")).toHaveText(new RegExp(`^5 people · ${title}$`, "i"));
    expect(harness.requests.find((r) => r.url.includes("/board"))!.url).toContain(`window=${windowName}`);
  });
}

test("a Window the widget doesn't know reads as Today", async ({ page }) => {
  const harness = await open(page, { status: 200, body: board() }, `${WIDGET_URL}&window=month`);
  await expect(card(page).getByTestId("folio")).toHaveText(/^01 · Today$/i);
  expect(harness.requests.find((r) => r.url.includes("/board"))!.url).toContain("window=daily");
});

test("the hero's square field sits inside the card, behind its text", async ({ page }) => {
  await open(page, { status: 200, body: board() });
  await expect(rank(page)).toHaveText("#3");
  const squares = card(page).getByTestId("field").locator("i");
  expect(await squares.count()).toBeGreaterThan(20);
  const check = () =>
    page.evaluate(() => {
      const box = document.querySelector('[data-testid="card"]')!.getBoundingClientRect();
      const outside = Array.from(document.querySelectorAll('[data-testid="field"] i')).filter((el) => {
        const r = el.getBoundingClientRect();
        return r.left < box.left - 0.5 || r.top < box.top - 0.5 || r.right > box.right + 0.5 || r.bottom > box.bottom + 0.5;
      });
      const folio = document.querySelector('[data-testid="folio"]')!.getBoundingClientRect();
      // Faded out behind the folio row, as the app's mask does.
      const underFolio = Array.from(document.querySelectorAll('[data-testid="field"] i')).filter(
        (el) => el.getBoundingClientRect().bottom <= folio.bottom + 2,
      );
      return { outside: outside.length, underFolio: underFolio.length };
    });
  expect(await check()).toEqual({ outside: 0, underFolio: 0 });
  // Generated for the card's actual size, again after a resize.
  await page.setViewportSize({ width: 900, height: 500 });
  await expect.poll(check).toEqual({ outside: 0, underFolio: 0 });
  expect(await squares.count()).toBeGreaterThan(10);
});

test("polls every 5 minutes, keeps the board on a failed refresh, then turns stale after 20 minutes", async ({ page }) => {
  const harness = await open(page, { status: 200, body: board() });
  await expect(rank(page)).toHaveText("#3");

  harness.reply({ status: 503, body: { error: "unavailable", message: "x" } });
  await page.clock.runFor(5 * 60_000);
  await expect.poll(() => harness.requests.filter((r) => r.url.includes("/board")).length).toBe(2);
  await expect(rank(page)).toHaveText("#3");
  await expect(rows(page)).toHaveCount(5);
  await expect(page.locator("html")).not.toHaveAttribute("data-state", "stale");

  // updatedAt was 90 s before T0: past 20 minutes of data age it's stale.
  await page.clock.runFor(14 * 60_000);
  await expect(page.locator("html")).toHaveAttribute("data-state", "stale");
  await expect(rank(page)).toHaveText("#3");
  await expect(page.getByTestId("age")).toHaveText("Updated 20 min ago");
  // Live rank's stale step-down: the rank to grey, lime to deep lime; the age stays soft.
  expect(await color(rank(page))).toBe(MUTED);
  expect(await color(status(page))).toBe(LIME_DEEP);
  expect(await color(page.getByTestId("movement-line"))).toBe(LIME_DEEP);
  expect(await color(page.getByTestId("age"))).toBe(SOFT);
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

test("no rivals shows the trophy and your count in place of a rank", async ({ page }) => {
  await open(page, {
    status: 200,
    body: board(
      { rank: null, competitorCount: 1, contributions: 7, above: null, below: null, gapToPass: null, movementToday: 0 },
      [{ rank: 1, login: "addisonk", contributions: 7, movementToday: 0, isSelf: true }],
    ),
  });
  await expect(count(page)).toHaveText("7");
  await expect(count(page)).toBeVisible();
  await expect(rank(page)).toBeHidden();
  await expect(card(page).getByTestId("trophy-mark")).toBeVisible();
  await expect(status(page)).toHaveText("Just you so far");
  await expect(page.getByTestId("list-head")).toHaveText(/^1 person · today$/i);
  await expect(page.locator("body")).not.toContainText("#1 of 1");
  await expect(card(page)).not.toContainText("of 1");
  await screenshot(page, "no-rivals");
});

test("before your first count there's no rank: the trophy and a quiet wait", async ({ page }) => {
  await open(page, {
    status: 200,
    body: board({ rank: null, contributions: null, above: null, below: null, gapToPass: null, movementToday: 0 }, [
      { rank: 1, login: "jordan", contributions: 21, movementToday: 0, isSelf: false },
      { rank: 2, login: "addisonk", contributions: null, movementToday: 0, isSelf: true },
    ]),
  });
  await expect(card(page).getByTestId("trophy-mark")).toBeVisible();
  await expect(rank(page)).toBeHidden();
  await expect(card(page).getByTestId("rank-of")).toBeHidden();
  await expect(status(page)).toHaveText("Waiting for your first count");
  expect(await color(status(page))).toBe(SOFT);
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
  await expect(card(page).getByTestId("rank-of")).toHaveText("of 2");
  await expect(page.locator("body")).not.toContainText("to pass");
  await expect(page.getByTestId("age")).toHaveText("Updated 1 min ago");
});

test("a missing fragment says how to set the page up, without calling the relay", async ({ page }) => {
  const harness = await open(page, { status: 200, body: board() }, `${ORIGIN}/v1/widget`);
  await expect(page.getByText("installation=")).toBeVisible();
  expect(harness.requests.filter((r) => r.url.includes("/board"))).toHaveLength(0);
});

test("an unsupported size says so, hides the board and never calls the relay", async ({ page }) => {
  // The relay serves this page, already marked unsupported, for any size but small, medium and large (src/widget.ts).
  const html = readFileSync(path.join(WIDGET_DIR, "standby.html"), "utf8")
    .replace('data-state="loading"', 'data-state="unsupported"')
    .replace('<p class="message-title" id="message-title"></p>', '<p class="message-title" id="message-title">Size not supported</p>');
  const harness = await open(page, { status: 200, body: board() }, WIDGET_URL.replace("size=medium", "size=extraLarge"), html);
  await expect(page.getByText("Size not supported")).toBeVisible();
  await expect(page.locator(".panes")).toBeHidden();
  await page.clock.runFor(6 * 60 * 1000);
  expect(harness.requests.filter((r) => r.url.includes("/board"))).toHaveLength(0);
  await screenshot(page, "unsupported");
});

test("a rank change ticks your row's count up and swaps rows with transforms", async ({ page }) => {
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
  await expect(page.getByTestId("movement-line")).toHaveText("Up 2 today");
  // Your count ticks through the values in between.
  const seenCounts = new Set<string>();
  for (let i = 0; i < 20; i++) {
    seenCounts.add((await selfRow(page).locator(".row-count").textContent()) ?? "");
    await page.clock.runFor(100);
  }
  await expect(selfRow(page).locator(".row-count")).toHaveText("16");
  expect([...seenCounts].some((c) => c === "13" || c === "14" || c === "15")).toBe(true);
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
    // The rank always shows whole, inside the card.
    const cardBox = (await card(page).boundingBox())!;
    const rankBox = (await rank(page).boundingBox())!;
    expect(rankBox.x).toBeGreaterThanOrEqual(cardBox.x - 0.5);
    expect(rankBox.x + rankBox.width).toBeLessThanOrEqual(cardBox.x + cardBox.width + 0.5);
    expect(rankBox.y + rankBox.height).toBeLessThanOrEqual(cardBox.y + cardBox.height + 0.5);
    expect(await rank(page).evaluate((el) => el.scrollWidth <= el.clientWidth + 1)).toBe(true);
    if (name === "tile") {
      await expect(card(page).getByTestId("who-name")).toBeVisible();
      await expect(status(page)).toBeVisible();
      await expect(page.getByTestId("age")).toBeVisible();
    }
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

/** The colours a framed page's tones are checked on: each text role, the card and your row. */
async function tones(frame: { evaluate: Page["evaluate"] }) {
  return frame.evaluate(() => {
    const q = (selector: string) => document.querySelector(selector)!;
    const fg = (selector: string) => getComputedStyle(q(selector)).color;
    const card = getComputedStyle(q('[data-testid="card"]'));
    const self = getComputedStyle(q('[data-testid="row"][data-self="true"]'));
    return {
      secondary: {
        listHead: fg('[data-testid="list-head"]'),
        rowRank: fg('[data-testid="row"]:not([data-self="true"]) .row-rank'),
        selfRowRank: fg('[data-testid="row"][data-self="true"] .row-rank'),
        folio: fg('[data-testid="folio"]'),
        folioLabel: fg('[data-testid="folio-label"]'),
        whoHandle: fg('[data-testid="who-handle"]'),
        rankOf: fg('[data-testid="rank-of"]'),
        age: fg('[data-testid="age"]'),
        rowMovementDown: fg('[data-testid="row"] [data-testid="movement"][data-direction="down"]'),
      },
      login: fg('[data-testid="row"]:not([data-self="true"]) .name'),
      lime: {
        movementUp: fg('[data-testid="movement-line"]'),
        status: fg('[data-testid="status"]'),
        selfCount: fg('[data-testid="row"][data-self="true"] .row-count'),
        badge: getComputedStyle(q('[data-testid="row"][data-self="true"] .badge')).backgroundColor,
      },
      card: { bg: card.backgroundColor, border: card.borderTopColor },
      folioRule: getComputedStyle(q('[data-testid="card"] .folio')).borderBottomColor,
      selfRow: { bg: self.backgroundColor, border: self.borderTopColor },
      avatar: getComputedStyle(q(".row .avatar")).backgroundColor,
    };
  });
}

test("on its own the page paints Committed's ink background", async ({ page }) => {
  await open(page, { status: 200, body: board() });
  await expect(rank(page)).toHaveText("#3");
  const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  expect(bg).toBe("rgb(5, 5, 5)");
});

test("on its own the page keeps Committed's fixed greys and its solid card", async ({ page }) => {
  await open(page, { status: 200, body: board() });
  await expect(rank(page)).toHaveText("#3");
  const t = await tones(page);
  expect(t.secondary.listHead).toBe(MUTED);
  expect(t.secondary.rowRank).toBe(MUTED);
  expect(t.secondary.selfRowRank).toBe(MUTED);
  for (const key of ["folio", "folioLabel", "whoHandle", "rankOf", "age", "rowMovementDown"] as const) {
    expect(t.secondary[key], key).toBe(SOFT);
  }
  expect(t.card.bg).toBe("rgb(14, 16, 11)");
  expect(t.selfRow).toEqual({ bg: "rgba(200, 255, 46, 0.08)", border: "rgba(200, 255, 46, 0.32)" });
});

test("embedded in another screen's frame, the page is transparent so the host's tile shows through", async ({ page }) => {
  const HOST = "https://host.test/";
  await page.route(HOST, (route) =>
    route.fulfill({
      status: 200,
      contentType: "text/html",
      body: `<!doctype html><body style="margin:0;background:#141416"><iframe id="w" src="${WIDGET_URL}" style="border:0;width:1280px;height:1080px"></iframe></body>`,
    })
  );
  await open(page, { status: 200, body: board() }, HOST);
  const frame = page.frameLocator("#w");
  await expect(frame.getByTestId("rank")).toHaveText("#3");
  const widget = page.frames().find((f) => f.url().startsWith(ORIGIN))!;
  const bgs = await widget.evaluate(() => [
    getComputedStyle(document.documentElement).backgroundColor,
    getComputedStyle(document.body).backgroundColor,
  ]);
  expect(bgs).toEqual(["rgba(0, 0, 0, 0)", "rgba(0, 0, 0, 0)"]);
  // No rendering-mode message from the host: fullColor, beside embedded.
  expect(await htmlClasses(widget)).toEqual(["embedded", "rendering-full-color"]);

  // Glance's tile may be flat or glass, so the page draws with Apple's vibrant tokens, not fixed
  // greys (Glance's ADR 0004): label-secondary for supporting text, label-primary for the rest,
  // separator for hairlines.
  const t = await tones(widget);
  for (const [role, value] of Object.entries(t.secondary)) expect(value, role).toBe(LABEL_SECONDARY);
  expect(t.login).toBe("rgb(255, 255, 255)");
  expect(t.card.border).toBe(SEPARATOR);
  expect(t.folioRule).toBe(SEPARATOR);
  // The card's solid tile becomes a translucent dark (fill-secondary's white lit it too much on
  // glass), so the surface shows through it.
  expect(t.card.bg).toBe("rgba(0, 0, 0, 0.25)");
  // Committed's lime, your row's highlight and the avatars are unchanged.
  expect(t.lime).toEqual({ movementUp: LIME, status: LIME, selfCount: LIME, badge: LIME });
  expect(t.selfRow).toEqual({ bg: "rgba(200, 255, 46, 0.08)", border: "rgba(200, 255, 46, 0.32)" });
  expect(t.avatar).toBe("rgb(27, 29, 23)");
});

test("embedded and stale, the stepped-down colours are label-secondary too", async ({ page }) => {
  const HOST = "https://host.test/";
  await page.route(HOST, (route) =>
    route.fulfill({
      status: 200,
      contentType: "text/html",
      body: `<!doctype html><body style="margin:0;background:#141416"><iframe id="w" src="${WIDGET_URL}" style="border:0;width:1280px;height:1080px"></iframe></body>`,
    })
  );
  await open(page, { status: 200, body: board({ updatedAt: NOW - 45 * 60 }) }, HOST);
  await expect(page.frameLocator("#w").getByTestId("rank")).toHaveText("#3");
  const widget = page.frames().find((f) => f.url().startsWith(ORIGIN))!;
  await expect.poll(() => widget.evaluate(() => document.documentElement.getAttribute("data-state"))).toBe("stale");
  const stale = await widget.evaluate(() => {
    const fg = (selector: string) => getComputedStyle(document.querySelector(selector)!).color;
    return {
      rank: fg('[data-testid="rank"]'),
      row: fg('[data-testid="row"]:not([data-self="true"])'),
      rowRank: fg('[data-testid="row"]:not([data-self="true"]) .row-rank'),
      rowMovementDown: fg('[data-testid="row"] [data-testid="movement"][data-direction="down"]'),
      status: fg('[data-testid="status"]'),
    };
  });
  for (const key of ["rank", "row", "rowRank", "rowMovementDown"] as const) expect(stale[key], key).toBe(LABEL_SECONDARY);
  expect(stale.status).toBe(LIME_DEEP);
});

// MARK: Rendering modes: Glance posts { type: "glance:rendering-mode", renderingMode } to the frame

const WHITE = "rgb(255, 255, 255)";
const NIGHT_RED = "rgb(255, 69, 58)";
/** Apple's fills (dark), as plain alpha white. */
const FILL_PRIMARY = "rgba(255, 255, 255, 0.2)";
const FILL_SECONDARY = "rgba(255, 255, 255, 0.07)";

/**
 * The widget in Glance's place: a host page frames it and, like Glance, posts the rendering mode
 * on the frame's load. Returns the widget's frame once the board is on screen.
 */
async function framed(page: Page, reply: Reply, renderingMode?: unknown, src = WIDGET_URL) {
  const HOST = "https://host.test/";
  const post =
    renderingMode === undefined
      ? ""
      : ` onload='this.contentWindow.postMessage(${JSON.stringify({ type: "glance:rendering-mode", renderingMode })}, "*")'`;
  await page.route(HOST, (route) =>
    route.fulfill({
      status: 200,
      contentType: "text/html",
      body: `<!doctype html><body style="margin:0;background:#141416"><iframe id="w" src="${src}"${post} style="border:0;width:1280px;height:1080px"></iframe></body>`,
    })
  );
  await open(page, reply, HOST);
  await expect(page.frameLocator("#w").getByTestId("rank")).toHaveText("#3");
  return page.frames().find((f) => f.url().startsWith(ORIGIN))!;
}

/** Posts a rendering mode to the widget from the host page, as Glance does when the mode changes. */
async function hostPosts(page: Page, message: unknown) {
  await page.evaluate((m) => (document.getElementById("w") as HTMLIFrameElement).contentWindow!.postMessage(m, "*"), message);
}

test("accented: Glance's message turns every colour white, with Apple's hierarchy and fills", async ({ page }) => {
  const widget = await framed(page, { status: 200, body: board() }, "accented");
  await expect.poll(() => htmlClasses(widget)).toEqual(["embedded", "rendering-accented"]);
  const t = await tones(widget);
  for (const [role, value] of Object.entries(t.secondary)) expect(value, role).toBe(LABEL_SECONDARY);
  expect(t.login).toBe(WHITE);
  // Committed's lime goes white; the "you" badge is a selected chip (fill-primary) with white text.
  expect(t.lime).toEqual({ movementUp: WHITE, status: WHITE, selfCount: WHITE, badge: FILL_PRIMARY });
  expect(await color(page.frameLocator("#w").locator(".badge"))).toBe(WHITE);
  // The rank card and your row use Apple's fills in place of the dark card and the lime tint.
  expect(t.card).toEqual({ bg: FILL_SECONDARY, border: SEPARATOR });
  expect(t.selfRow).toEqual({ bg: FILL_SECONDARY, border: FILL_PRIMARY });
  expect(t.avatar).toBe(FILL_SECONDARY);
});

/** Every element that paints text or an icon in currentColor, with its colour. */
async function inkColours(frame: { evaluate: Page["evaluate"] }) {
  return frame.evaluate(() => {
    const out: Record<string, string> = {};
    for (const el of Array.from(document.querySelectorAll("body *"))) {
      const paintsText = Array.from(el.childNodes).some((n) => n.nodeType === 3 && n.nodeValue!.trim());
      if (!paintsText && el.tagName.toLowerCase() !== "svg") continue;
      const box = el.getBoundingClientRect();
      if (!box.width || !box.height) continue;
      out[`${el.tagName.toLowerCase()}.${el.getAttribute("class") ?? ""} ${(el.textContent ?? "").trim().slice(0, 20)}`] =
        getComputedStyle(el).color;
    }
    return out;
  });
}

test("vibrant: Night Mode draws every piece of text in the full night red", async ({ page }) => {
  const widget = await framed(page, { status: 200, body: board() }, "vibrant");
  await expect.poll(() => htmlClasses(widget)).toEqual(["embedded", "rendering-vibrant"]);
  const ink = await inkColours(widget);
  expect(Object.keys(ink).length).toBeGreaterThan(15);
  // No alpha hierarchy: a 60% red would be about 2.3:1 on black.
  for (const [what, value] of Object.entries(ink)) expect(value, what).toBe(NIGHT_RED);
  const t = await tones(widget);
  // Fills and hairlines are decorative, so they're the night red at Apple's fill alphas.
  expect(t.card).toEqual({ bg: "rgba(255, 69, 58, 0.07)", border: "rgba(255, 69, 58, 0.1)" });
  expect(t.selfRow).toEqual({ bg: "rgba(255, 69, 58, 0.07)", border: "rgba(255, 69, 58, 0.2)" });
  expect(t.lime.badge).toBe("rgba(255, 69, 58, 0.2)");
});

test("vibrant and stale, the stepped-down colours stay the full night red", async ({ page }) => {
  const widget = await framed(page, { status: 200, body: board({ updatedAt: NOW - 45 * 60 }) }, "vibrant");
  await expect.poll(() => widget.evaluate(() => document.documentElement.getAttribute("data-state"))).toBe("stale");
  await expect.poll(() => htmlClasses(widget)).toEqual(["embedded", "rendering-vibrant"]);
  for (const [what, value] of Object.entries(await inkColours(widget))) expect(value, what).toBe(NIGHT_RED);
});

test("a rendering-mode message from anyone but the framing page is ignored", async ({ page }) => {
  const widget = await framed(page, { status: 200, body: board() }, "accented");
  await expect.poll(() => htmlClasses(widget)).toEqual(["embedded", "rendering-accented"]);
  const seen = await countModeMessages(widget);
  // The widget's own window, and a second frame inside the host page, post vibrant.
  await widget.evaluate(() => window.postMessage({ type: "glance:rendering-mode", renderingMode: "vibrant" }, "*"));
  await page.evaluate(() => {
    const other = document.createElement("iframe");
    document.body.appendChild(other);
    (other.contentWindow as unknown as { eval: (code: string) => void }).eval(
      "parent.document.getElementById('w').contentWindow.postMessage({ type: 'glance:rendering-mode', renderingMode: 'vibrant' }, '*')"
    );
  });
  await expect.poll(seen).toBe(2);
  expect(await htmlClasses(widget)).toEqual(["embedded", "rendering-accented"]);
});

/** Counts rendering-mode messages in the widget once its own listener has handled them. */
async function countModeMessages(widget: { evaluate: Page["evaluate"] }) {
  await widget.evaluate(() => {
    const w = window as unknown as { seen: number };
    w.seen = 0;
    window.addEventListener("message", (e) => {
      if (e.data && typeof e.data === "object" && "renderingMode" in e.data) w.seen += 1;
    });
  });
  return () => widget.evaluate(() => (window as unknown as { seen: number }).seen);
}

test("an unknown rendering mode, or another message type, is ignored", async ({ page }) => {
  const widget = await framed(page, { status: 200, body: board() }, "accented");
  await expect.poll(() => htmlClasses(widget)).toEqual(["embedded", "rendering-accented"]);
  const seen = await countModeMessages(widget);
  for (const renderingMode of ["neon", "Vibrant", "toString", "", null, 1]) {
    await hostPosts(page, { type: "glance:rendering-mode", renderingMode });
  }
  await hostPosts(page, { type: "glance:theme", renderingMode: "vibrant" });
  await hostPosts(page, "glance:rendering-mode vibrant");
  await expect.poll(seen).toBe(7);
  expect(await htmlClasses(widget)).toEqual(["embedded", "rendering-accented"]);
  // fullColor afterwards takes the page back to its framed tones.
  await hostPosts(page, { type: "glance:rendering-mode", renderingMode: "fullColor" });
  await expect.poll(() => htmlClasses(widget)).toEqual(["embedded", "rendering-full-color"]);
  const t = await tones(widget);
  expect(t.lime).toEqual({ movementUp: LIME, status: LIME, selfCount: LIME, badge: LIME });
  expect(t.card.bg).toBe("rgba(0, 0, 0, 0.25)");
});

test("Glance changes the mode on a frame already showing the board, and a resize keeps it", async ({ page }) => {
  const widget = await framed(page, { status: 200, body: board() });
  await hostPosts(page, { type: "glance:rendering-mode", renderingMode: "vibrant" });
  await expect.poll(() => htmlClasses(widget)).toEqual(["embedded", "rendering-vibrant"]);
  // A tall frame stacks the panes; the mode stays.
  await page.evaluate(() => {
    const w = document.getElementById("w")!;
    w.style.width = "400px";
    w.style.height = "900px";
  });
  await expect.poll(() => htmlClasses(widget)).toEqual(["embedded", "rendering-vibrant", "stacked"]);
});

test("?renderingMode= forces a mode on the page's own address, the token still in the fragment", async ({ page }) => {
  const url = `${ORIGIN}/v1/widget?size=medium&renderingMode=accented#installation=${INSTALLATION}&token=${TOKEN}`;
  const harness = await open(page, { status: 200, body: board() }, url);
  await expect(rank(page)).toHaveText("#3");
  expect(await htmlClasses(page)).toEqual(["rendering-accented"]);
  expect(await color(page.getByTestId("status"))).toBe(WHITE);
  expect(await color(page.getByTestId("age"))).toBe(LABEL_SECONDARY);
  expect(harness.requests.some((r) => r.url.includes(TOKEN))).toBe(false);
  // Unframed, nothing can post: a message from the page itself is ignored.
  await page.evaluate(() => window.postMessage({ type: "glance:rendering-mode", renderingMode: "vibrant" }, "*"));
  await page.waitForTimeout(50);
  expect(await htmlClasses(page)).toEqual(["rendering-accented"]);
});

test("?renderingMode= pins the mode: Glance's messages don't override it", async ({ page }) => {
  // A TV capture forces Night Mode by day, while Glance posts fullColor on load and on changes.
  const src = `${ORIGIN}/v1/widget?size=medium&renderingMode=vibrant#installation=${INSTALLATION}&token=${TOKEN}`;
  const widget = await framed(page, { status: 200, body: board() }, "fullColor", src);
  const seen = await countModeMessages(widget);
  await hostPosts(page, { type: "glance:rendering-mode", renderingMode: "accented" });
  await hostPosts(page, { type: "glance:rendering-mode", renderingMode: "fullColor" });
  await expect.poll(seen).toBe(2);
  expect(await htmlClasses(widget)).toEqual(["embedded", "rendering-vibrant"]);
});

test("an unknown ?renderingMode= pins nothing: Glance's message still sets the mode", async ({ page }) => {
  const src = `${ORIGIN}/v1/widget?size=medium&renderingMode=night#installation=${INSTALLATION}&token=${TOKEN}`;
  const widget = await framed(page, { status: 200, body: board() }, "accented", src);
  await expect.poll(() => htmlClasses(widget)).toEqual(["embedded", "rendering-accented"]);
});

test("an unknown ?renderingMode= falls back to fullColor", async ({ page }) => {
  await open(page, { status: 200, body: board() }, `${ORIGIN}/v1/widget?size=medium&renderingMode=night#installation=${INSTALLATION}&token=${TOKEN}`);
  await expect(rank(page)).toHaveText("#3");
  expect(await htmlClasses(page)).toEqual(["rendering-full-color"]);
});

test("the setup and size-not-supported messages take the mode too", async ({ page }) => {
  await open(page, { status: 200, body: board() }, `${ORIGIN}/v1/widget?size=medium&renderingMode=vibrant`);
  await expect(page.locator("#message-title")).toHaveText("Add this screen's board token");
  expect(await htmlClasses(page)).toEqual(["rendering-vibrant"]);
  expect(await color(page.locator("#message-title"))).toBe(NIGHT_RED);
  expect(await color(page.locator("#message-detail"))).toBe(NIGHT_RED);
});

/** A 1×1 lime PNG, standing in for a GitHub avatar. */
const AVATAR = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGPYcVQBAAOYAa1Jk6JEAAAAAElFTkSuQmCC",
  "base64"
);

/** Apple renders images greyscale in accented, and Night Mode tints them red (a static filter; Glance measured 41 fps on the Frame). */
const AVATAR_FILTERS = [
  ["fullColor", "none"],
  ["accented", "grayscale(1)"],
  ["vibrant", "grayscale(1) brightness(0.35) sepia(1) saturate(4) hue-rotate(-45deg)"],
] as const;

for (const [mode, filter] of AVATAR_FILTERS) {
  test(`avatars in ${mode}: filter ${filter}, fully opaque`, async ({ page }) => {
    const url = `${ORIGIN}/v1/widget?size=medium&renderingMode=${mode}#installation=${INSTALLATION}&token=${TOKEN}`;
    await open(page, { status: 200, body: board() }, url, undefined, AVATAR);
    await expect(page.locator(".row .avatar.loaded")).toHaveCount(5);
    await expect(page.locator("#who-avatar")).toHaveClass(/loaded/);
    for (const img of [page.locator(".row .avatar img").first(), page.locator("#who-avatar img")]) {
      await expect.poll(() => img.evaluate((el) => getComputedStyle(el).opacity)).toBe("1");
      expect(await img.evaluate((el) => getComputedStyle(el).filter)).toBe(filter);
    }
  });
}

// MARK: Small and large: the iPhone widget's other sizes, at Glance's tile sizes

/** Glance's tile boxes (ADR 0002 in addisonk/glance). */
const TILES = { small: [440, 492], medium: [912, 492], large: [912, 1016] } as const;
const urlFor = (size: string, query = "") => `${ORIGIN}/v1/widget?size=${size}${query}#installation=${INSTALLATION}&token=${TOKEN}`;
const mini = (page: Page) => page.getByTestId("mini");
const miniRank = (page: Page) => page.getByTestId("mini-rank");
const miniCount = (page: Page) => page.getByTestId("mini-count");
const miniStatus = (page: Page) => page.getByTestId("mini-status");

/** Fourteen people, you tenth: below the large widget's six leaders. */
function longBoard(overrides: Record<string, unknown> = {}) {
  const many: Row[] = Array.from({ length: 14 }, (_, i) => ({
    rank: i + 1,
    login: i === 9 ? "addisonk" : `rival-number-${i + 1}`,
    contributions: 40 - i * 2,
    movementToday: i === 9 ? 1 : i % 3 === 0 ? 1 : 0,
    isSelf: i === 9,
  }));
  return board(
    { rank: 10, contributions: 22, above: { login: "rival-number-9", contributions: 24, movementToday: 0 }, gapToPass: 2, ...overrides },
    many,
  );
}

/** Elements drawn outside the page's box, and the page's scroll size. */
const overflowOf = (frame: { evaluate: Page["evaluate"] }) =>
  frame.evaluate(() => {
    const root = document.documentElement;
    const bad: string[] = [];
    document.querySelectorAll("body *").forEach((el) => {
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) return;
      if (r.left < -0.5 || r.top < -0.5 || r.right > root.clientWidth + 0.5 || r.bottom > root.clientHeight + 0.5) {
        bad.push(`${el.tagName}.${el.getAttribute("class")} ${Math.round(r.left)},${Math.round(r.top)},${Math.round(r.right)},${Math.round(r.bottom)}`);
      }
    });
    return { bad, scrollW: root.scrollWidth - root.clientWidth, scrollH: root.scrollHeight - root.clientHeight };
  });

test("small: before the first board, a quiet placeholder and never zero", async ({ page }) => {
  await page.setViewportSize({ width: 440, height: 492 });
  await open(page, "hang", urlFor("small"));
  await expect(page.locator("html")).toHaveAttribute("data-size", "small");
  await expect(mini(page)).toBeVisible();
  await expect(miniRank(page)).toHaveText("–");
  await expect(miniStatus(page)).toHaveText("Your board is loading");
  await expect(page.getByTestId("mini-count-line")).toBeHidden();
  await expect(page.locator("body")).not.toContainText(/\b0\b/);
  await screenshot(page, "small-first-load");
});

test("small: the iPhone's small widget — the Window, your rank, your count, square and streak, then the age", async ({ page }) => {
  await page.setViewportSize({ width: 440, height: 492 });
  const harness = await open(page, { status: 200, body: board({ streak: 12 }) }, urlFor("small"));
  await expect(miniRank(page)).toHaveText("#3");
  await expect(mini(page).getByTestId("window-title")).toHaveText("Today");
  await expect(miniCount(page)).toHaveText("12");
  expect(await color(miniCount(page))).toBe(LIME);
  await expect(page.getByTestId("mini-square")).toHaveAttribute("data-level", "4");
  await expect(page.getByTestId("mini-streak")).toBeVisible();
  await expect(page.getByTestId("mini-streak")).toHaveText("12");
  await expect(miniStatus(page)).toHaveText("Updated 1 min ago");
  // No rows, no "of N", no card: the iPhone's small widget is read at a glance.
  await expect(card(page)).toBeHidden();
  await expect(page.getByTestId("board")).toBeHidden();
  await expect(rows(page)).toHaveCount(0);
  await expect(page.locator("body")).not.toContainText("of 5");
  // Top to bottom: the Window, the rank, the count, the age.
  const top = async (id: string) => (await mini(page).getByTestId(id).boundingBox())!.y;
  expect(await top("window-title")).toBeLessThan(await top("mini-rank"));
  expect(await top("mini-rank")).toBeLessThan(await top("mini-count"));
  expect(await top("mini-count")).toBeLessThan(await top("mini-status"));
  // The same board call, token in the header only; no avatars to fetch.
  const boardCalls = harness.requests.filter((r) => r.url.includes("/board"));
  expect(boardCalls).toHaveLength(1);
  expect(boardCalls[0]!.authorization).toBe(`Bearer ${TOKEN}`);
  for (const request of harness.requests) expect(request.url).not.toContain(TOKEN);
  expect(harness.requests.filter((r) => r.url.includes("github"))).toHaveLength(0);
  await screenshot(page, "small");
});

test("small: a streak shows from 2 days, and past GitHub's year as 365+", async ({ page }) => {
  await page.setViewportSize({ width: 440, height: 492 });
  const harness = await open(page, { status: 200, body: board({ streak: 1 }) }, urlFor("small"));
  await expect(miniRank(page)).toHaveText("#3");
  await expect(page.getByTestId("mini-streak")).toBeHidden();
  harness.reply({ status: 200, body: board({ streak: 400, updatedAt: NOW + 200 }) });
  await page.clock.runFor(5 * 60_000);
  await expect(page.getByTestId("mini-streak")).toHaveText("365+");
});

test("small: with no rivals your count takes the rank's place", async ({ page }) => {
  await page.setViewportSize({ width: 440, height: 492 });
  await open(
    page,
    {
      status: 200,
      body: board(
        { rank: null, competitorCount: 1, contributions: 7, streak: 4, above: null, below: null, gapToPass: null, movementToday: 0 },
        [{ rank: 1, login: "addisonk", contributions: 7, movementToday: 0, isSelf: true }],
      ),
    },
    urlFor("small"),
  );
  await expect(miniCount(page)).toHaveText("7");
  await expect(miniRank(page)).toBeHidden();
  await expect(miniStatus(page)).toHaveText("Just you so far");
  // At the rank's size, not the count's.
  const sizes = await page.evaluate(() => {
    const px = (sel: string) => parseFloat(getComputedStyle(document.querySelector(sel)!).fontSize);
    return { count: px("#mini-count"), rem: parseFloat(getComputedStyle(document.documentElement).fontSize) };
  });
  expect(sizes.count).toBeGreaterThan(sizes.rem * 6);
  await expect(page.locator("body")).not.toContainText("#1");
  await screenshot(page, "small-no-rivals");
});

test("small: before your first count, a dash for the rank and the count, and what it waits for", async ({ page }) => {
  await page.setViewportSize({ width: 440, height: 492 });
  await open(
    page,
    {
      status: 200,
      body: board({ rank: null, contributions: null, streak: 5, above: null, below: null, gapToPass: null, movementToday: 0 }, [
        { rank: 1, login: "jordan", contributions: 21, movementToday: 0, isSelf: false },
        { rank: 2, login: "addisonk", contributions: null, movementToday: 0, isSelf: true },
      ]),
    },
    urlFor("small"),
  );
  await expect(miniStatus(page)).toHaveText("Waiting for your first count");
  await expect(miniRank(page)).toHaveText("–");
  await expect(miniCount(page)).toHaveText("–");
  await expect(page.getByTestId("mini-square")).toHaveAttribute("data-level", "0");
  await expect(page.getByTestId("mini-streak")).toBeHidden();
});

test("small: stale steps the colours down, as Live rank's do", async ({ page }) => {
  await page.setViewportSize({ width: 440, height: 492 });
  await open(page, { status: 200, body: board({ streak: 12, updatedAt: NOW - 45 * 60 }) }, urlFor("small"));
  await expect(page.locator("html")).toHaveAttribute("data-state", "stale");
  expect(await color(miniRank(page))).toBe(MUTED);
  expect(await color(miniCount(page))).toBe(LIME_DEEP);
  expect(await page.getByTestId("mini-square").evaluate((el) => getComputedStyle(el).backgroundColor)).toBe("rgb(106, 168, 26)");
});

test("large: before the first board, the Window and a quiet wait, never zero", async ({ page }) => {
  await page.setViewportSize({ width: 912, height: 1016 });
  await open(page, "hang", urlFor("large"));
  await expect(page.locator("html")).toHaveAttribute("data-size", "large");
  await expect(page.getByTestId("board-head").getByTestId("window-title")).toHaveText("Today");
  await expect(page.getByTestId("board-status")).toHaveText("Your board is loading");
  await expect(card(page)).toBeHidden();
  await expect(page.locator("body")).not.toContainText(/\b0\b/);
});

test("large: the iPhone's large widget — the six leaders, then you below a rule", async ({ page }) => {
  await page.setViewportSize({ width: 912, height: 1016 });
  const harness = await open(page, { status: 200, body: longBoard() }, urlFor("large"));
  await expect(rows(page)).toHaveCount(7);
  for (let i = 0; i < 6; i++) {
    await expect(rows(page).nth(i)).toContainText(`#${i + 1}`);
    await expect(rows(page).nth(i)).toHaveAttribute("data-detached", "false");
  }
  const me = rows(page).nth(6);
  await expect(me).toHaveAttribute("data-self", "true");
  await expect(me).toHaveAttribute("data-detached", "true");
  await expect(me).toContainText("#10");
  await expect(me).toContainText("you");
  await expect(me.getByTestId("movement")).toHaveAttribute("data-direction", "up");
  // The rule sits between the leaders and you.
  const rule = await me.evaluate((el) => {
    const before = getComputedStyle(el, "::before");
    return { content: before.content, height: before.height, bg: before.backgroundColor };
  });
  expect(rule).toEqual({ content: '""', height: "1px", bg: "rgba(142, 146, 136, 0.4)" });
  // LiveRankHeader: the Window on the left, the age on the right; no card, no "N people" eyebrow.
  const head = page.getByTestId("board-head");
  await expect(head.getByTestId("window-title")).toHaveText("Today");
  await expect(page.getByTestId("board-age")).toHaveText("Updated 1 min ago");
  expect((await head.getByTestId("window-title").boundingBox())!.x).toBeLessThan((await page.getByTestId("board-age").boundingBox())!.x);
  await expect(card(page)).toBeHidden();
  await expect(page.getByTestId("list-head")).toBeHidden();
  await expect(page.getByTestId("board-status")).toBeHidden();
  // No hidden card loading your avatar: only the seven rows' avatars are asked for.
  await expect.poll(() => harness.requests.filter((r) => r.url.startsWith("https://github.com/")).length).toBe(7);
  await screenshot(page, "large");
});

test("large: among the leaders, you're in your place and there's no rule", async ({ page }) => {
  await page.setViewportSize({ width: 912, height: 1016 });
  await open(page, { status: 200, body: board() }, urlFor("large"));
  await expect(rows(page)).toHaveCount(5);
  await expect(rows(page).nth(2)).toHaveAttribute("data-self", "true");
  await expect(page.locator('[data-testid="row"][data-detached="true"]')).toHaveCount(0);
});

test("large: you below the leaders without a count stay off the board, as on the iPhone", async ({ page }) => {
  await page.setViewportSize({ width: 912, height: 1016 });
  const body = longBoard({ rank: null, contributions: null, above: null, gapToPass: null });
  (body.rows as Row[])[9]!.contributions = null;
  await open(page, { status: 200, body }, urlFor("large"));
  await expect(rows(page)).toHaveCount(6);
  await expect(page.locator('[data-testid="row"][data-self="true"]')).toHaveCount(0);
});

test("large: a rank change slides the rows, and you join the leaders", async ({ page }) => {
  await page.setViewportSize({ width: 912, height: 1016 });
  const harness = await open(page, { status: 200, body: longBoard() }, urlFor("large"));
  await expect(rows(page).nth(6)).toHaveAttribute("data-detached", "true");
  const climbed = longBoard({ rank: 6, contributions: 31, updatedAt: NOW + 290 });
  const list = climbed.rows as Row[];
  const me = list.splice(9, 1)[0]!;
  list.splice(5, 0, { ...me, contributions: 31 });
  list.forEach((row, i) => (row.rank = i + 1));
  harness.reply({ status: 200, body: climbed });
  await page.clock.runFor(5 * 60_000);
  await expect(rows(page)).toHaveCount(6);
  await expect(rows(page).nth(5)).toHaveAttribute("data-self", "true");
  await expect(rows(page).nth(5)).toHaveAttribute("data-detached", "false");
});

for (const [size, [width, height]] of Object.entries(TILES)) {
  for (const mode of ["fullColor", "accented", "vibrant"] as const) {
    test(`${size} fills Glance's ${width}×${height} tile in ${mode} without overflowing`, async ({ page }) => {
      await page.setViewportSize({ width, height });
      const HOST = "https://host.test/";
      const post = JSON.stringify({ type: "glance:rendering-mode", renderingMode: mode });
      await page.route(HOST, (route) =>
        route.fulfill({
          status: 200,
          contentType: "text/html",
          body: `<!doctype html><body style="margin:0;background:#141416"><iframe id="w" src="${urlFor(size)}" scrolling="no" onload='this.contentWindow.postMessage(${post}, "*")' style="border:0;display:block;width:${width}px;height:${height}px"></iframe></body>`,
        })
      );
      await open(page, { status: 200, body: longBoard({ streak: 12 }) }, HOST);
      const frame = page.frameLocator("#w");
      await expect(frame.locator("html")).toHaveAttribute("data-state", "live");
      const widget = page.frames().find((f) => f.url().startsWith(ORIGIN))!;
      await expect.poll(() => htmlClasses(widget)).toEqual(["embedded", `rendering-${mode === "fullColor" ? "full-color" : mode}`]);
      expect(await widget.evaluate(() => document.documentElement.getAttribute("data-size"))).toBe(size);
      await widget.evaluate(() => document.fonts.ready);
      // Transparent, so Glance's surface shows through.
      expect(await widget.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe("rgba(0, 0, 0, 0)");
      const overflow = await overflowOf(widget);
      expect(overflow.bad).toEqual([]);
      expect(overflow.scrollW).toBeLessThanOrEqual(0);
      expect(overflow.scrollH).toBeLessThanOrEqual(0);
      if (size === "small") {
        await expect(frame.getByTestId("mini-rank")).toHaveText("#10");
        await expect(frame.getByTestId("mini-count")).toHaveText("22");
        await expect(frame.getByTestId("mini-streak")).toHaveText("12");
      } else if (size === "large") {
        await expect(frame.getByTestId("row")).toHaveCount(7);
      } else {
        await expect(frame.getByTestId("rank")).toHaveText("#10");
      }
      const ink = await inkColours(widget);
      expect(Object.keys(ink).length).toBeGreaterThan(3);
      if (mode === "vibrant") {
        for (const [what, value] of Object.entries(ink)) expect(value, what).toBe(NIGHT_RED);
      } else if (mode === "accented") {
        // Everything is white, at Apple's label alphas: no lime left.
        for (const [what, value] of Object.entries(ink)) expect([WHITE, LABEL_SECONDARY], what).toContain(value);
      } else {
        // Committed's own colours stay in fullColor: lime, the streak mark's deep lime, and the
        // avatars' initials (the avatars don't change when framed).
        for (const [what, value] of Object.entries(ink)) {
          expect([WHITE, LABEL_SECONDARY, LIME, ...(/initials|streak-mark|badge/.test(what) ? [SOFT, LIME_DEEP, "rgb(30, 36, 16)"] : [])], what).toContain(value);
        }
      }
      await screenshot(page, `tile-${size}-${mode}`);
    });
  }
}

for (const size of ["small", "large"] as const) {
  test(`${size}: framed, the supporting text is label-secondary`, async ({ page }) => {
    const [width, height] = TILES[size];
    await page.setViewportSize({ width, height });
    const HOST = `https://host.test/${size}`;
    await page.route(HOST, (route) =>
      route.fulfill({
        status: 200,
        contentType: "text/html",
        body: `<!doctype html><body style="margin:0;background:#141416"><iframe id="w" src="${urlFor(size)}" style="border:0;width:${width}px;height:${height}px"></iframe></body>`,
      })
    );
    await open(page, { status: 200, body: longBoard({ streak: 12 }) }, HOST);
    const frame = page.frameLocator("#w");
    await expect(frame.locator("html")).toHaveAttribute("data-state", "live");
    const head = frame.locator(size === "small" ? '[data-testid="mini"]' : '[data-testid="board-head"]');
    expect(await color(head.getByTestId("window-title")), size).toBe(LABEL_SECONDARY);
    expect(await color(frame.getByTestId(size === "small" ? "mini-status" : "board-age")), size).toBe(LABEL_SECONDARY);
    if (size === "small") expect(await color(frame.locator(".streak-number"))).toBe(LABEL_SECONDARY);
    // Committed's lime is its own: the trophy keeps it in fullColor.
    expect(await color(head.locator(".trophy"))).toBe(LIME);
  });
}

for (const size of ["small", "large"] as const) {
  test(`${size}: the messages fit the tile too`, async ({ page }) => {
    const [width, height] = TILES[size];
    await page.setViewportSize({ width, height });
    await open(page, { status: 403, body: { error: "revoked", message: "x" } }, urlFor(size));
    await expect(page.getByText("This screen's access was revoked")).toBeVisible();
    await expect(page.locator(".panes")).toBeHidden();
    expect((await overflowOf(page)).bad).toEqual([]);
    await screenshot(page, `${size}-revoked`);
  });

  test(`${size}: without a fragment it says how to set up this size`, async ({ page }) => {
    const [width, height] = TILES[size];
    await page.setViewportSize({ width, height });
    await open(page, { status: 200, body: board() }, `${ORIGIN}/v1/widget?size=${size}`);
    await expect(page.locator("#message-detail")).toContainText(`/v1/widget?size=${size}#installation=`);
    expect((await overflowOf(page)).bad).toEqual([]);
  });
}
