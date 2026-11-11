// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { mockIPC, clearMocks } from "@tauri-apps/api/mocks";
import { start } from "./app";
import { sampleBoard, samplePeople, samplePerson } from "./sample-board";
import type { PersonView } from "./types";

const board = {
  window: "today",
  owner: "octocat",
  refreshing: false,
  error: null,
  people_error: null,
  last_updated: 1779969600,
  people_updated: 1779969600,
  rows: [
    {
      login: "octocat",
      name: "Mona",
      avatar_url: null,
      rank: 1,
      contributions: 12,
      streak: null,
      is_you: true,
      movement: 0,
      status: "loaded",
    },
  ],
};
afterEach(() => {
  clearMocks();
  document.body.innerHTML = "";
});
async function mount(snapshot: unknown, calls: string[] = []) {
  mockIPC((command, args) => {
    calls.push(command);
    if (command === "get_board") return snapshot;
    if (command === "get_settings")
      return {
        notifications: false,
        automatic_updates: true,
        private_tip_dismissed: false,
      };
    if (command === "get_desktop_settings")
      return { launch_at_login: false, version: "0.1.50" };
    if (command === "plugin:event|listen") return 1;
    return null;
  });
  document.body.innerHTML = '<main id="app"></main>';
  return start(document.querySelector("main")!, "board");
}
test("board presents rank, name, contributions and you to assistive technology", async () => {
  const dispose = await mount(board);
  expect(
    document.querySelector(
      '[aria-label="Rank 1, Mona, 12 Contributions, you"]',
    ),
  ).not.toBeNull();
  expect(document.body.textContent).toContain("Today");
  dispose();
});
test("a trolling row turns its count red and swaps the squares for the troll face", async () => {
  const trolling = {
    ...board,
    rows: [
      {
        ...board.rows[0],
        contributions: 784,
        burst: { date: "2026-05-28", count: 784, usual: 102 },
      },
    ],
  };
  const dispose = await mount(trolling);
  expect(document.querySelector(".contributions.troll")?.textContent).toBe(
    "784",
  );
  const face = document.querySelector<HTMLElement>(".troll-face");
  expect(face?.title).toBe(
    "Problem? 784 in one day, about 7 times their usual big day.",
  );
  expect(document.querySelector(".contribution-squares")).toBeNull();
  expect(
    document.querySelector(
      '[aria-label="Rank 1, Mona, 784 Contributions, you, trolling: 784 in one day, about 7 times their usual big day"]',
    ),
  ).not.toBeNull();
  dispose();
});
test("keyboard time-range switching selects the core window and requests only a stale refresh", async () => {
  const calls: string[] = [];
  const dispose = await mount(board, calls);
  const announcer = document.querySelector(".sr-only");
  const today = document.querySelector<HTMLButtonElement>(
    '[data-window="today"]',
  )!;
  today.focus();
  today.dispatchEvent(
    new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }),
  );
  await vi.waitFor(() =>
    expect(
      document
        .querySelector('[data-window="week"]')
        ?.getAttribute("aria-checked"),
    ).toBe("true"),
  );
  expect(calls).toContain("select_window");
  expect(calls).toContain("request_refresh");
  expect(document.activeElement?.getAttribute("data-window")).toBe("week");
  expect(document.querySelector(".sr-only")).toBe(announcer);
  expect(announcer?.textContent).toContain("7 days");
  dispose();
});
test("first refresh explains missing counts without inventing zeroes", async () => {
  const dispose = await mount({
    ...board,
    refreshing: true,
    last_updated: null,
    rows: [{ ...board.rows[0], contributions: null, status: "loading" }],
  });
  expect(document.querySelector(".status")?.textContent).toContain(
    "Fetching the first set of standings",
  );
  expect(document.querySelector(".contributions")?.textContent).toBe("—");
  dispose();
});
test("a failed refresh keeps saved numbers and announces failure", async () => {
  const dispose = await mount({
    ...board,
    error: "Saved numbers are still shown.",
    rows: [{ ...board.rows[0], status: "failed" }],
  });
  expect(document.querySelector(".contributions")?.textContent).toBe("12");
  expect(document.querySelector(".status")?.textContent).toContain("errors");
  expect(document.body.textContent).toContain("Saved numbers are still shown.");
  dispose();
});
test("streaks show on rows and your summary from 2 days, read as N-day streak", async () => {
  const row = (login: string, rank: number, streak: number | null) => ({
    ...board.rows[0],
    login,
    name: null,
    rank,
    is_you: false,
    contributions: streak === null ? null : 3,
    streak,
  });
  const dispose = await mount({
    ...board,
    rows: [
      { ...board.rows[0], streak: 12 },
      row("year", 2, 371),
      row("exactly", 3, 365),
      row("pair", 4, 2),
      row("single", 5, 1),
      row("broken", 6, 0),
      row("unloaded", 7, null),
    ],
  });
  const label = (login: string) =>
    document
      .querySelector(`[data-open-person="${login}"]`)
      ?.getAttribute("aria-label");
  const flame = (login: string) =>
    document.querySelector(`[data-open-person="${login}"] .streak`)
      ?.textContent;
  expect(label("octocat")).toBe(
    "Rank 1, Mona, 12 Contributions, 12-day streak, you",
  );
  expect(flame("octocat")).toBe("🔥 12");
  expect(document.querySelector(".summary .streak")?.textContent).toBe("🔥 12");
  const summaryStreak = document.querySelector(".summary .streak");
  expect(summaryStreak?.getAttribute("role")).toBe("img");
  expect(summaryStreak?.getAttribute("aria-label")).toBe("12-day streak");
  expect(flame("year")).toBe("🔥 365+");
  expect(label("year")).toContain("3 Contributions, 365-plus-day streak");
  expect(flame("exactly")).toBe("🔥 365");
  expect(label("exactly")).toContain("365-day streak");
  expect(flame("pair")).toBe("🔥 2");
  for (const login of ["single", "broken", "unloaded"]) {
    expect(flame(login)).toBeUndefined();
    expect(label(login)).not.toContain("streak");
  }
  // The flame is decoration; the row's label carries the streak.
  expect(
    document
      .querySelector('[data-open-person="octocat"] .streak')
      ?.getAttribute("aria-hidden"),
  ).toBe("true");
  dispose();
});
test("no streak in your summary below 2 days or without data", async () => {
  const dispose = await mount({
    ...board,
    rows: [{ ...board.rows[0], streak: 1 }],
  });
  expect(document.querySelector(".summary .streak")).toBeNull();
  dispose();
});
test("the fixture page's Sample board renders every streak case", async () => {
  const dispose = await mount(sampleBoard("today", 1779969600));
  const flames = [...document.querySelectorAll(".standing .streak")].map(
    (flame) => flame.textContent,
  );
  expect(flames).toEqual(["🔥 365+", "🔥 23", "🔥 12", "🔥 2"]);
  expect(document.querySelector(".summary .streak")?.textContent).toBe("🔥 12");
  dispose();
});
test("the picker offers three Windows and keyboard navigation wraps across them", async () => {
  const dispose = await mount(board);
  const labels = [...document.querySelectorAll("[data-window]")].map(
    (button) => [button.getAttribute("data-window"), button.textContent],
  );
  expect(labels).toEqual([
    ["today", "Today"],
    ["week", "7 days"],
    ["monthly", "30 days"],
  ]);
  const press = async (key: string, expected: string) => {
    (document.activeElement as HTMLElement).dispatchEvent(
      new KeyboardEvent("keydown", { key, bubbles: true }),
    );
    await vi.waitFor(() =>
      expect(document.activeElement?.getAttribute("data-window")).toBe(
        expected,
      ),
    );
  };
  document.querySelector<HTMLButtonElement>('[data-window="today"]')!.focus();
  await press("ArrowLeft", "monthly");
  await press("ArrowRight", "today");
  await press("ArrowRight", "week");
  await press("End", "monthly");
  await press("ArrowLeft", "week");
  await press("Home", "today");
  dispose();
});
test("movement chevrons show on Today only", async () => {
  const windows: unknown[] = [];
  mockIPC((command, args) => {
    if (command === "get_board") {
      const window = (args as { window: string }).window;
      windows.push(window);
      // The core owns movement: it reports it on Today, 0 on the others.
      const movement = window === "today" ? 2 : 0;
      return { ...board, window, rows: [{ ...board.rows[0], movement }] };
    }
    if (command === "get_settings")
      return {
        notifications: false,
        automatic_updates: true,
        private_tip_dismissed: false,
      };
    if (command === "get_desktop_settings")
      return { launch_at_login: false, version: "0.1.50" };
    if (command === "plugin:event|listen") return 1;
    return null;
  });
  document.body.innerHTML = '<main id="app"></main>';
  const dispose = await start(document.querySelector("main")!, "board");
  expect(document.querySelector(".status")?.textContent).toContain("Today ·");
  expect(
    document.querySelector('.movement[aria-label="Moved up 2"]'),
  ).not.toBeNull();
  document.querySelector<HTMLButtonElement>('[data-window="monthly"]')!.click();
  await vi.waitFor(() =>
    expect(document.querySelector(".status")?.textContent).toContain(
      "30 days ·",
    ),
  );
  expect(windows).toContain("monthly");
  expect(document.querySelector(".movement")).toBeNull();
  dispose();
});

const october = [
  4, 0, 7, 12, 0, 3, 9, 1, 0, 0, 6, 2, 8, 0, 5, 1, 1, 0, 3, 0, 7, 2, 0, 4, 11,
  0, 6, 0, 2, 3, 9,
];
const person: PersonView = {
  login: "odile-m",
  name: "Odile M.",
  avatar_url: null,
  is_you: false,
  status: "loaded",
  month: "2026-11-01",
  month_name: "November",
  last_month: "2026-10-01",
  last_month_name: "October",
  day_of_month: 4,
  days_in_month: 30,
  history: {
    this_month: [3, 0, 41, 5],
    last_month: october,
    current_streak: 2,
    longest_streak: 371,
    active_days: 3,
  },
};
async function mountPerson(
  view: PersonView | null,
  calls: [string, unknown][] = [],
) {
  mockIPC((command, args) => {
    calls.push([command, args]);
    if (command === "get_person") return view;
    if (command === "get_board") return board;
    if (command === "get_settings")
      return {
        notifications: false,
        automatic_updates: true,
        private_tip_dismissed: true,
      };
    if (command === "get_desktop_settings")
      return { launch_at_login: false, version: "0.1.50" };
    if (command === "plugin:event|listen") return 1;
    return null;
  });
  document.body.innerHTML = '<main id="app"></main>';
  return start(document.querySelector("main")!, "person");
}
const caption = () =>
  document.querySelector(".selected-day")?.textContent?.replace(/\s+/g, " ");

test("clicking a row opens that person's view in its own window", async () => {
  const calls: [string, unknown][] = [];
  mockIPC((command, args) => {
    calls.push([command, args]);
    if (command === "get_board") return sampleBoard("today", 1779969600);
    if (command === "get_settings")
      return {
        notifications: false,
        automatic_updates: true,
        private_tip_dismissed: true,
      };
    if (command === "get_desktop_settings")
      return { launch_at_login: false, version: "0.1.50" };
    if (command === "plugin:event|listen") return 1;
    return null;
  });
  document.body.innerHTML = '<main id="app"></main>';
  const dispose = await start(document.querySelector("main")!, "board");
  document
    .querySelector<HTMLButtonElement>('[data-open-person="odile-m"]')!
    .click();
  await vi.waitFor(() =>
    expect(calls).toContainEqual(["open_person", { login: "odile-m" }]),
  );
  expect(calls.some(([command]) => command === "open_profile")).toBe(false);
  dispose();
});

test("the person view shows this month's bars over last month's, streaks and active days", async () => {
  const dispose = await mountPerson(person);
  expect(document.querySelector("h1")?.textContent).toContain("Odile M.");
  const chart = document.querySelector("svg.chart")!;
  expect(chart.getAttribute("aria-label")).toBe(
    "3 active days this month, most on November 3 with 41",
  );
  // One reachable bar per day so far; last month's 31 days in grey behind them.
  const days = document.querySelectorAll("[data-day]");
  expect(days).toHaveLength(4);
  expect(days[2].getAttribute("aria-label")).toBe(
    "November 3: 41 contributions. October 3: 7",
  );
  expect(document.querySelectorAll(".past-bar")).toHaveLength(31);
  // Today is selected to start with, and only it is in the tab order.
  expect(caption()).toContain("November 4 · 5 contributions");
  expect(Array.from(days).map((day) => day.getAttribute("tabindex"))).toEqual([
    "-1",
    "-1",
    "-1",
    "0",
  ]);
  const stats = document.querySelector(".person-stats")!.textContent!;
  expect(stats).toMatch(/Current streak\s*2 days/);
  expect(stats).toMatch(/Longest streak\s*365\+ days/);
  // Read aloud like the rows' "365-plus-day streak", not "365 plus sign days".
  const longest = document.querySelectorAll(".person-stats dd")[1];
  expect(longest.querySelector('[aria-hidden="true"]')?.textContent).toBe(
    "365+ days",
  );
  expect(longest.querySelector(".sr-only")?.textContent).toBe("365-plus days");
  expect(stats).toMatch(/Active days\s*3 of 4/);
  dispose();
});

test("arrow keys, Home, End and clicks select a bar and show its date and count", async () => {
  const dispose = await mountPerson(person);
  const day = (n: number) =>
    document.querySelector<SVGElement>(`[data-day="${n}"]`)!;
  day(4).focus();
  day(4).dispatchEvent(
    new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true }),
  );
  await vi.waitFor(() =>
    expect(caption()).toContain("November 3 · 41 contributions"),
  );
  expect(caption()).toContain("October 3 · 7");
  expect(document.activeElement).toBe(day(3));
  expect(day(3).getAttribute("tabindex")).toBe("0");
  day(3).dispatchEvent(
    new KeyboardEvent("keydown", { key: "Home", bubbles: true }),
  );
  await vi.waitFor(() =>
    expect(caption()).toContain("November 1 · 3 contributions"),
  );
  day(1).dispatchEvent(
    new KeyboardEvent("keydown", { key: "End", bubbles: true }),
  );
  await vi.waitFor(() => expect(caption()).toContain("November 4"));
  day(2).dispatchEvent(new MouseEvent("click", { bubbles: true }));
  await vi.waitFor(() =>
    expect(caption()).toContain("November 2 · 0 contributions"),
  );
  dispose();
});

const limitsCopy =
  "Contributions count activity, not how good or hard the work was. Automated commits and bots count like anyone’s, and private work counts only when its owner turns on private contributions.";
test("your own person view says what the number can't show (#89), loaded or waiting", async () => {
  let dispose = await mountPerson(person);
  expect(document.querySelector(".limits-note")).toBeNull();
  dispose();
  for (const history of [person.history, null]) {
    dispose = await mountPerson({ ...person, is_you: true, history });
    const note = document.querySelector(".limits-note")!;
    expect(note.querySelector("h2")?.textContent).toBe(
      "What this number can’t show",
    );
    expect(note.querySelector("p")?.textContent).toBe(limitsCopy);
    dispose();
  }
});
test("before their count loads the person view says it's waiting instead of drawing zeros", async () => {
  const dispose = await mountPerson({ ...person, history: null });
  expect(document.querySelector(".waiting")?.textContent).toContain(
    "Waiting for Odile M.’s count",
  );
  expect(document.querySelector("svg.chart")).toBeNull();
  expect(document.querySelector(".person-stats")).toBeNull();
  dispose();
});

test("the GitHub link opens their profile, and only your own view has the private-contributions tip", async () => {
  const calls: [string, unknown][] = [];
  let dispose = await mountPerson(person, calls);
  expect(document.querySelector(".person-tip")).toBeNull();
  document.querySelector<HTMLButtonElement>('[data-action="github"]')!.click();
  await vi.waitFor(() =>
    expect(calls).toContainEqual(["open_profile", { login: "odile-m" }]),
  );
  dispose();
  dispose = await mountPerson({ ...person, is_you: true });
  // Shown even after the board's tip was dismissed: this is where it matters.
  expect(document.querySelector(".person-tip")?.textContent).toContain(
    "Private contributions",
  );
  dispose();
});

test("the fixture's Sample people have consistent person views", () => {
  const now = Math.floor(new Date("2026-11-22T12:00:00").getTime() / 1000);
  for (const { login } of samplePeople) {
    const view = samplePerson(login, now)!;
    if (login === "niko-vane") {
      expect(view.history).toBeNull();
      continue;
    }
    const history = view.history!;
    const sample = samplePeople.find((p) => p.login === login)!;
    const row = sampleBoard("today", now).rows.find((r) => r.login === login)!;
    expect(history.this_month).toHaveLength(22);
    expect(history.this_month.reduce((a, b) => a + b, 0)).toBe(
      sample.thisMonth,
    );
    expect(history.this_month[21]).toBe(row.contributions);
    expect(history.last_month).toHaveLength(31);
    expect(history.last_month.reduce((a, b) => a + b, 0)).toBe(
      sample.lastMonth ?? 0,
    );
    expect(
      [...history.this_month, ...history.last_month].every((n) => n >= 0),
    ).toBe(true);
    expect(history.active_days).toBe(
      history.this_month.filter((n) => n > 0).length,
    );
    expect(history.current_streak).toBe(row.streak);
    expect(history.longest_streak).toBeGreaterThanOrEqual(
      history.current_streak,
    );
  }
  expect(samplePerson("stranger", now)).toBeNull();
});
