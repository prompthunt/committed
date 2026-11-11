// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { mockIPC, clearMocks } from "@tauri-apps/api/mocks";
import { emit } from "@tauri-apps/api/event";
import { start } from "./app";
import { sampleBoard, samplePeople, samplePerson } from "./sample-board";
import type { PersonView, Window } from "./types";

const board = {
  window: "today",
  owner: "octocat",
  refreshing: false,
  error: null,
  people_error: null,
  last_updated: 1779969600,
  people_updated: 1779969600,
  day_of_month: 10,
  days_in_month: 30,
  final_standings: null,
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
  expect(label("year")).toContain("3 Contributions, 365+ day streak");
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
test("the picker offers This month fourth and keyboard navigation wraps across all four", async () => {
  const dispose = await mount(board);
  const labels = [...document.querySelectorAll("[data-window]")].map(
    (button) => [button.getAttribute("data-window"), button.textContent],
  );
  expect(labels).toEqual([
    ["today", "Today"],
    ["week", "7 days"],
    ["monthly", "30 days"],
    ["month", "This month"],
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
  await press("ArrowLeft", "month");
  await press("ArrowRight", "today");
  await press("End", "month");
  await press("ArrowLeft", "monthly");
  await press("Home", "today");
  dispose();
});
test("This month shows the day of the month and today's movement", async () => {
  const calls: string[] = [];
  const windows: unknown[] = [];
  mockIPC((command, args) => {
    calls.push(command);
    if (command === "get_board") {
      windows.push((args as { window: string }).window);
      return {
        ...board,
        window: (args as { window: string }).window,
        rows: [{ ...board.rows[0], movement: 2 }],
      };
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
  expect(document.querySelector(".status")?.textContent).not.toContain("Day");
  document.querySelector<HTMLButtonElement>('[data-window="month"]')!.click();
  await vi.waitFor(() =>
    expect(document.querySelector(".status")?.textContent).toContain(
      "This month · Day 10 of 30 ·",
    ),
  );
  expect(windows).toContain("month");
  expect(
    document.querySelector('.movement[aria-label="Moved up 2"]'),
  ).not.toBeNull();
  expect(document.querySelector(".sr-only")?.textContent).toContain(
    "Day 10 of 30",
  );
  document.querySelector<HTMLButtonElement>('[data-window="monthly"]')!.click();
  await vi.waitFor(() =>
    expect(document.querySelector(".status")?.textContent).toContain(
      "30 days ·",
    ),
  );
  expect(document.querySelector(".status")?.textContent).not.toContain("Day");
  expect(document.querySelector(".movement")).toBeNull();
  dispose();
});
// Nov 1 2026, noon UTC: the 1st everywhere from UTC-11 to UTC+11.
const firstOfNovember = Date.UTC(2026, 10, 1, 12) / 1000;
test("on the 1st the board opens on last month's Final standings with medals", async () => {
  const dispose = await mount(sampleBoard("today", firstOfNovember));
  const toggle = document.querySelector<HTMLButtonElement>(
    '[data-action="final"]',
  )!;
  expect(toggle.textContent).toContain("October final");
  expect(toggle.getAttribute("aria-pressed")).toBe("true");
  expect(document.querySelector(".status")?.textContent).toBe(
    "October final · You finished #2 of 6",
  );
  expect(document.querySelector(".sr-only")?.textContent).toBe(
    "October final · You finished #2 of 6",
  );
  expect(
    [...document.querySelectorAll(".standing .medal")].map(
      (medal) => medal.textContent,
    ),
  ).toEqual(["🥇", "🥈", "🥉"]);
  for (const spoken of [
    "Rank 1, Ines Volk, 212 Contributions, gold medal",
    "Rank 2, Ari Linden, 160 Contributions, silver medal, you",
    "Rank 3, Odile M., 160 Contributions, bronze medal",
    "Rank 5, Bram Ott, 0 Contributions",
    "Rank 6, Niko Vane, Contributions unavailable",
  ])
    expect(
      document.querySelector(`[aria-label="${spoken}"]`),
      spoken,
    ).not.toBeNull();
  expect(document.querySelector(".summary-count")?.textContent).toBe(
    "160In October",
  );
  // No Window is the list while Final standings shows, and no flames or movement either.
  expect(document.querySelector('[aria-checked="true"]')).toBeNull();
  expect(document.querySelector(".standing .streak")).toBeNull();
  expect(document.querySelector(".movement")).toBeNull();

  // The toggle goes back to the live board, which never shows medals, and keeps focus.
  toggle.focus();
  toggle.click();
  await vi.waitFor(() =>
    expect(
      document
        .querySelector('[data-action="final"]')
        ?.getAttribute("aria-pressed"),
    ).toBe("false"),
  );
  expect(document.activeElement?.getAttribute("data-action")).toBe("final");
  expect(document.querySelector(".medal")).toBeNull();
  expect(
    document
      .querySelector('[data-window="today"]')
      ?.getAttribute("aria-checked"),
  ).toBe("true");
  expect(document.querySelector(".status")?.textContent).toContain("Today ·");
  document.querySelector<HTMLButtonElement>('[data-action="final"]')!.click();
  await vi.waitFor(() =>
    expect(document.querySelectorAll(".medal")).toHaveLength(3),
  );
  // Choosing a Window shows that Window.
  document.querySelector<HTMLButtonElement>('[data-window="month"]')!.click();
  await vi.waitFor(() =>
    expect(document.querySelector(".status")?.textContent).toContain(
      "This month · Day 1 of 30",
    ),
  );
  expect(document.querySelector(".medal")).toBeNull();
  dispose();
});
test("other days offer no Final standings", async () => {
  const dispose = await mount(sampleBoard("today", 1779969600));
  expect(document.querySelector('[data-action="final"]')).toBeNull();
  expect(document.querySelector(".medal")).toBeNull();
  dispose();
});
test("each new 1st opens on Final standings again, even after picking a Window last month", async () => {
  // The board's webview lives for weeks in the tray, so a Window picked on one 1st must not
  // keep the next 1st's Final standings closed.
  let now = firstOfNovember;
  mockIPC(
    (command, args) => {
      if (command === "get_board")
        return sampleBoard((args as { window: Window }).window, now);
      if (command === "get_settings")
        return {
          notifications: false,
          automatic_updates: true,
          private_tip_dismissed: true,
        };
      if (command === "get_desktop_settings")
        return { launch_at_login: false, version: "0.1.50" };
      return null;
    },
    { shouldMockEvents: true },
  );
  document.body.innerHTML = '<main id="app"></main>';
  const dispose = await start(document.querySelector("main")!, "board");
  const pressed = () =>
    document
      .querySelector('[data-action="final"]')
      ?.getAttribute("aria-pressed");
  document.querySelector<HTMLButtonElement>('[data-window="week"]')!.click();
  await vi.waitFor(() => expect(pressed()).toBe("false"));
  // Nov 20: nothing to offer. Dec 1: the board opens on November's final again.
  now = Date.UTC(2026, 10, 20, 12) / 1000;
  await emit("board-changed");
  await vi.waitFor(() => expect(pressed()).toBeUndefined());
  now = Date.UTC(2026, 11, 1, 12) / 1000;
  await emit("board-changed");
  await vi.waitFor(() => expect(pressed()).toBe("true"));
  expect(document.querySelector(".status")?.textContent).toContain(
    "November final",
  );
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
    finishes: [
      {
        month: "2026-10-01",
        month_name: "October",
        rank: 1,
        of: 6,
        total: 105,
        medal: "gold",
      },
      {
        month: "2025-12-01",
        month_name: "December",
        rank: 4,
        of: 6,
        total: 40,
        medal: null,
      },
    ],
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

test("the person view shows this month's bars over last month's, streaks, active days and finishes", async () => {
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
  expect(stats).toMatch(/Active days\s*3 of 4/);
  const finishes = Array.from(document.querySelectorAll(".finishes li"), (li) =>
    li.getAttribute("aria-label"),
  );
  expect(finishes).toEqual([
    "October: #1 of 6, 105 contributions, gold medal",
    "December 2025: #4 of 6, 40 contributions",
  ]);
  expect(document.querySelector(".finishes li")?.textContent).toContain("🥇");
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
    const board = sampleBoard("month", now);
    const row = board.rows.find((r) => r.login === login)!;
    expect(history.this_month).toHaveLength(22);
    expect(history.this_month.reduce((a, b) => a + b, 0)).toBe(
      row.contributions,
    );
    expect(history.this_month[21]).toBe(
      sampleBoard("today", now).rows.find((r) => r.login === login)!
        .contributions,
    );
    expect(history.last_month).toHaveLength(31);
    expect(history.last_month.reduce((a, b) => a + b, 0)).toBe(
      samplePeople.find((p) => p.login === login)!.lastMonth ?? 0,
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
    expect(history.finishes[0].month_name).toBe("October");
  }
  expect(samplePerson("stranger", now)).toBeNull();
});
