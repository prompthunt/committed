// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { mockIPC, clearMocks } from "@tauri-apps/api/mocks";
import { emit } from "@tauri-apps/api/event";
import { start } from "./app";
import { sampleBoard } from "./sample-board";
import type { Window } from "./types";

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
      .querySelector(`[data-profile="${login}"]`)
      ?.getAttribute("aria-label");
  const flame = (login: string) =>
    document.querySelector(`[data-profile="${login}"] .streak`)?.textContent;
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
      .querySelector('[data-profile="octocat"] .streak')
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
