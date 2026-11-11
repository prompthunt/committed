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

async function open(page: Page, first: Reply, url = WIDGET_URL, html?: string): Promise<Harness> {
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
const color = (locator: ReturnType<Page["locator"]>) => locator.evaluate((el) => getComputedStyle(el).color);

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
  // The relay serves this page, already marked unsupported, for any size but medium (src/widget.ts).
  const html = readFileSync(path.join(WIDGET_DIR, "standby.html"), "utf8")
    .replace('data-state="loading"', 'data-state="unsupported"')
    .replace('<p class="message-title" id="message-title"></p>', '<p class="message-title" id="message-title">Size not supported</p>');
  const harness = await open(page, { status: 200, body: board() }, WIDGET_URL.replace("size=medium", "size=large"), html);
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

test("on its own the page paints Committed's ink background", async ({ page }) => {
  await open(page, { status: 200, body: board() });
  await expect(rank(page)).toHaveText("#3");
  const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  expect(bg).toBe("rgb(5, 5, 5)");
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
});
