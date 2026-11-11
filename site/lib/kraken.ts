/**
 * Committed on an NZXT Kraken LCD (gitcommitted.app/kraken), through NZXT CAM's Web
 * Integration. CAM loads the same URL twice: a Configuration Browser (no query) for setup,
 * and the Kraken Browser (`?kraken=1`) that draws the LCD. Both share this origin's
 * localStorage, which carries the settings from one to the other.
 *
 * Counts come from the Committed relay's public `GET /v1/board`: github.com's contribution
 * pages can't be read from a browser (no CORS), and the relay already reads and caches them.
 */

export type KrakenWindow = "daily" | "weekly" | "monthly" | "month";

export const WINDOW_LABELS: Record<KrakenWindow, string> = {
  daily: "Today",
  weekly: "7 days",
  monthly: "30 days",
  month: "This month",
};

export interface Person {
  login: string;
  avatar: string;
}

export interface KrakenSettings {
  login: string;
  avatar: string;
  /** Everyone loaded from GitHub (people you follow) plus anyone added by hand. */
  people: Person[];
  /** The rivals on your Kraken board: a subset of `people`, without you. */
  competitors: string[];
  window: KrakenWindow;
  timeZone: string;
}

/** The relay's `LiveRankState`, as `GET /v1/board` returns it. */
export interface BoardState {
  window: KrakenWindow;
  rank: number | null;
  competitorCount: number;
  contributions: number | null;
  above: { login: string; contributions: number } | null;
  below: { login: string; contributions: number } | null;
  updatedAt: number;
}

export const RELAY_URL = process.env.NEXT_PUBLIC_COMMITTED_RELAY_URL ?? "https://committed-relay.prompt-hunt.workers.dev";
export const KRAKEN_URL = "https://gitcommitted.app/kraken";
export const STORAGE_KEY = "committed.kraken.v1";
/** The relay's cap counts you, so 99 rivals. */
export const MAX_RIVALS = 99;
/** Like Live rank and the widgets: colors step down 20 minutes past the data. */
export const STALE_AFTER_SECONDS = 20 * 60;
export const POLL_MS = 60_000;

const LOGIN = /^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,38}$/i;

export function normalizeLogin(raw: string): string | null {
  const login = raw.trim().replace(/^@/, "").toLowerCase();
  return LOGIN.test(login) ? login : null;
}

export function localTimeZone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

export function loadSettings(): KrakenSettings | null {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as KrakenSettings;
    return parsed && typeof parsed.login === "string" && Array.isArray(parsed.competitors) ? parsed : null;
  } catch {
    return null;
  }
}

export function saveSettings(settings: KrakenSettings): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  } catch {
    // Storage blocked: the settings link still carries everything.
  }
}

/** Settings carried in the URL (`?login=&competitors=&window=`), for a link pasted into CAM. */
export function settingsFromQuery(params: URLSearchParams): KrakenSettings | null {
  const login = normalizeLogin(params.get("login") ?? "");
  if (!login) return null;
  const competitors = (params.get("competitors") ?? "")
    .split(",")
    .map(normalizeLogin)
    .filter((entry): entry is string => entry !== null && entry !== login);
  const window = params.get("window");
  return {
    login,
    avatar: "",
    people: [],
    competitors,
    window: window !== null && window in WINDOW_LABELS ? (window as KrakenWindow) : "daily",
    timeZone: params.get("tz") ?? localTimeZone(),
  };
}

export function settingsLink(settings: KrakenSettings): string {
  const query = new URLSearchParams({
    login: settings.login,
    competitors: settings.competitors.join(","),
    window: settings.window,
  });
  return `${KRAKEN_URL}?${query.toString().replaceAll("%2C", ",")}`;
}

export function boardUrl(settings: KrakenSettings): string {
  const query = new URLSearchParams({
    login: settings.login,
    competitors: settings.competitors.join(","),
    window: settings.window,
    tz: settings.timeZone,
  });
  return `${RELAY_URL}/v1/board?${query.toString()}`;
}

export class GitHubLookupError extends Error {}

/** You and everyone you follow, from GitHub's public API (anonymous: 60 requests an hour). */
export async function lookUpPeople(rawLogin: string): Promise<{ self: Person; following: Person[] }> {
  const login = normalizeLogin(rawLogin);
  if (!login) throw new GitHubLookupError("That isn’t a GitHub username.");
  const get = async (path: string) => {
    const response = await fetch(`https://api.github.com${path}`, { headers: { accept: "application/vnd.github+json" } });
    if (response.status === 404) throw new GitHubLookupError(`GitHub has no user named ${login}.`);
    if (response.status === 403 || response.status === 429) {
      throw new GitHubLookupError("GitHub is limiting requests from this network. Try again in a few minutes.");
    }
    if (!response.ok) throw new GitHubLookupError(`GitHub answered ${response.status}. Try again.`);
    return response.json();
  };
  const user = (await get(`/users/${login}`)) as { login: string; avatar_url: string };
  const following: Person[] = [];
  for (let page = 1; page <= 10; page++) {
    const batch = (await get(`/users/${login}/following?per_page=100&page=${page}`)) as {
      login: string;
      avatar_url: string;
    }[];
    following.push(...batch.map((entry) => ({ login: entry.login.toLowerCase(), avatar: entry.avatar_url })));
    if (batch.length < 100) break;
  }
  return { self: { login: user.login.toLowerCase(), avatar: user.avatar_url }, following };
}

/** "13 min" / "2 hr" / "just now", for the age line. */
export function ageText(seconds: number): string {
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  return `${hours} hr ago`;
}

/** "3 to pass alice", matching `LiveRankState.passLine` in the apps (you win ties on your own board). */
export function passLine(state: BoardState): string | null {
  if (!state.above || state.contributions === null) return null;
  return `${Math.max(state.above.contributions - state.contributions, 1)} to pass ${state.above.login}`;
}
