import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { GLYPH_PATH } from "../../site/lib/glyph";
import type {
  Board,
  Burst,
  DesktopSettings,
  Person,
  PersonView,
  PersonVisibility,
  Settings,
  Window,
} from "./types";

// Reuse the site's trophy and the approved app tile instead of drawing substitutes.
const brandMark = `<svg class="brand-mark" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="${GLYPH_PATH}" /></svg>`;
const appIcon = new URL(
  "../../docs/design/committed-app-icon.svg",
  import.meta.url,
).href;
const trollFace = new URL("./assets/troll.png", import.meta.url).href;
/** "784 in one day, about 7 times their usual big day": the tooltip and spoken trolling note. */
function trolling(burst: Burst): string {
  const multiple =
    burst.usual > 0 ? Math.floor(burst.count / burst.usual) : null;
  return `${burst.count.toLocaleString()} in one day${multiple ? `, about ${multiple} times their usual big day` : ""}`;
}
const windows: [Window, string][] = [
  ["today", "Today"],
  ["week", "7 days"],
  ["monthly", "30 days"],
];
const escape = (value: unknown) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
const name = (p: Person) => p.name?.trim() || p.login;
const count = (value: number | null) =>
  value === null ? "—" : value.toLocaleString();
// A streak shows from 2 days. GitHub's calendar covers about a year, so above 365 it reads
// "365+" (spoken "365-plus"): the run may have started before the calendar does. Swift's
// `StreakLabel` has the same rules.
const streakCap = 365;
function streakText(streak: number | null | undefined) {
  if (streak == null || streak < 2) return null;
  return streak > streakCap ? `${streakCap}+` : String(streak);
}
/** "12-day streak", or "365-plus-day streak" past the calendar. */
const streakSpoken = (text: string) =>
  `${text.replace(/\+$/, "-plus")}-day streak`;
const age = (timestamp: number | null) =>
  timestamp === null
    ? "Not refreshed yet"
    : `Updated ${Math.max(0, Math.floor((Date.now() / 1000 - timestamp) / 60))} min ago`;
const plural = (n: number, word: string) =>
  `${n.toLocaleString()} ${word}${n === 1 ? "" : "s"}`;
// The person view's streak stats read in days; past GitHub's year it's "365+ days", read aloud
// as "365-plus days".
const streakDays = (n: number) =>
  n > streakCap
    ? `<span aria-hidden="true">${streakCap}+ days</span><span class="sr-only">${streakCap}-plus days</span>`
    : plural(n, "day");
/** "18 active days this month, most on November 8 with 41": the chart's screen-reader summary. */
function chartSummary(view: PersonView, days: number[]) {
  const active = days.filter((n) => n > 0).length;
  if (!active) return "No contributions yet this month";
  const most = Math.max(...days);
  return `${plural(active, "active day")} this month, most on ${view.month_name} ${days.indexOf(most) + 1} with ${most.toLocaleString()}`;
}
/**
 * This month's bars (one per day so far, each reachable by keyboard and screen reader) in front
 * of last month's in grey, drawn as plain SVG. `selected` is the day shown in the caption.
 */
function chart(view: PersonView, selected: number) {
  const { this_month: now, last_month: past } = view.history!;
  const slots = Math.max(view.days_in_month, past.length);
  const slot = 10;
  const height = 120;
  const top = Math.max(1, ...now, ...past);
  const barHeight = (n: number) => (n / top) * (height - 4);
  const pastBars = past
    .map((n, i) => {
      const h = barHeight(n);
      return `<rect class="past-bar" x="${i * slot + 1}" y="${height - h}" width="${slot - 2}" height="${h}" rx="1.5" />`;
    })
    .join("");
  const days = now
    .map((n, i) => {
      const day = i + 1;
      const h = Math.max(2, barHeight(n));
      const last = past[i];
      const label = `${view.month_name} ${day}: ${plural(n, "contribution")}${last === undefined ? "" : `. ${view.last_month_name} ${day}: ${last.toLocaleString()}`}`;
      return `<g class="day ${day === selected ? "selected" : ""} ${n ? "" : "zero"}" data-day="${day}" data-focus="day-${day}" tabindex="${day === selected ? 0 : -1}" role="img" aria-label="${escape(label)}"><rect class="hit" x="${i * slot}" y="0" width="${slot}" height="${height}" /><rect class="bar" x="${i * slot + 2.5}" y="${height - h}" width="${slot - 5}" height="${h}" rx="1.5" /></g>`;
    })
    .join("");
  const ticks = [1, 8, 15, 22, 29]
    .filter((day) => day <= slots)
    .map(
      (day) =>
        `<text x="${(day - 0.5) * slot}" y="${height + 13}">${day}</text>`,
    )
    .join("");
  return `<svg class="chart" viewBox="0 0 ${slots * slot} ${height + 16}" role="group" aria-label="${escape(chartSummary(view, now))}"><g aria-hidden="true">${pastBars}</g>${days}<g class="ticks" aria-hidden="true">${ticks}</g></svg>`;
}
function selectedDay(view: PersonView, day: number) {
  const { this_month: now, last_month: past } = view.history!;
  const last = past[day - 1];
  return `<p class="selected-day"><strong>${view.month_name} ${day}</strong> · ${plural(now[day - 1], "contribution")}${last === undefined ? "" : ` <span class="muted">· ${view.last_month_name} ${day} · ${last.toLocaleString()}</span>`}</p>`;
}
/** The private-contributions tip, as on the Mac: always shown on your own person view. */
const privateTip = `<aside class="tip person-tip"><div><p><strong>Want your private work to count?</strong></p><p>Include private repo and org activity: on your GitHub profile, above the green squares, choose <strong>Contribution settings → Private contributions</strong>.</p><p>Only daily counts are shared. Your code and repo details stay private.</p><button data-action="contributions">Open GitHub profile settings</button></div></aside>`;
/** What the Contributions count can't show (#89), under your own person view, as on the Mac. */
const limitsNote = `<section class="limits-note" aria-labelledby="limits-title"><h2 id="limits-title">What this number can’t show</h2><p>Contributions count activity, not how good or hard the work was. Automated commits and bots count like anyone’s, and private work counts only when its owner turns on private contributions.</p></section>`;
function personHtml(view: PersonView, selected: number) {
  const history = view.history;
  const header = `<header class="person-header">${avatar(view)}<div class="identity"><h1>${escape(name(view))}</h1><small>@${escape(view.login)}${view.is_you ? " · you" : ""}</small></div><button data-action="github" data-login="${escape(view.login)}">GitHub profile</button></header>`;
  if (!history)
    return `${header}<section class="waiting" role="status"><p><strong>Waiting for ${escape(name(view))}’s count</strong></p><p class="muted">${view.status === "failed" ? "GitHub didn’t answer the last refresh. Committed tries again on the next one." : "Their month appears once the next refresh loads it."}</p></section>${view.is_you ? privateTip + limitsNote : ""}`;
  const total = (days: number[]) => days.reduce((a, b) => a + b, 0);
  return `${header}
    ${view.status === "failed" ? '<p class="muted">Refresh failed · showing saved counts</p>' : ""}
    <dl class="person-stats">
      <div><dt><span aria-hidden="true">🔥 </span>Current streak</dt><dd>${streakDays(history.current_streak)}</dd></div>
      <div><dt>Longest streak</dt><dd>${streakDays(history.longest_streak)}</dd></div>
      <div><dt>Active days</dt><dd>${history.active_days} of ${view.day_of_month}</dd></div>
    </dl>
    <section class="month" aria-labelledby="month-title"><div class="month-head"><h2 id="month-title">${escape(view.month_name)}</h2><p class="legend"><span class="key now" aria-hidden="true"></span>${escape(view.month_name)} <strong>${total(history.this_month).toLocaleString()}</strong><span class="key past" aria-hidden="true"></span>${escape(view.last_month_name)} <strong>${total(history.last_month).toLocaleString()}</strong></p></div>
      ${selectedDay(view, selected)}${chart(view, selected)}</section>
    ${view.is_you ? privateTip + limitsNote : ""}`;
}
function avatar(person: Person) {
  return `<span class="avatar fallback" data-avatar="${escape(person.login)}" aria-hidden="true">${escape(name(person).slice(0, 1).toUpperCase())}</span>`;
}
export async function start(
  root: HTMLElement,
  view: string,
): Promise<() => void> {
  root.className = `view-${view}`;
  let selected: Window = "today";
  let filter = "all";
  let search = "";
  let disposed = false;
  let pollTimer: ReturnType<typeof setTimeout> | undefined;
  let status = "";
  let updateReady = false;
  let loadRevision = 0;
  let errorMessage = "";
  // The person view's data and its selected bar (today until you pick another day).
  let personView: PersonView | null = null;
  let selectedBar = 0;
  let settings: Settings;
  let desktop: DesktopSettings;
  const avatars = new Map<string, Promise<string | null>>();
  const announcer = document.createElement("div");
  announcer.className = "sr-only";
  announcer.setAttribute("role", "status");
  announcer.setAttribute("aria-live", "polite");
  announcer.setAttribute("aria-atomic", "true");
  root.after(announcer);
  const act = async (command: string, args?: Record<string, unknown>) => {
    errorMessage = "";
    try {
      await invoke(command, args);
    } catch (error) {
      showError(String(error));
    }
  };
  function showError(error: string) {
    errorMessage = error;
    const alert = root.querySelector<HTMLElement>("#error");
    if (alert) {
      alert.textContent = error;
      alert.hidden = false;
    }
  }
  function replace(html: string) {
    const active = document.activeElement as HTMLInputElement | null;
    const focus = active?.dataset.focus;
    const selection =
      active?.tagName === "INPUT" ? active.selectionStart : null;
    const menuOpen = root.querySelector<HTMLDetailsElement>("details")?.open;
    root.innerHTML = html;
    for (const control of root.querySelectorAll<HTMLElement>(
      "button, input, select, summary",
    )) {
      control.dataset.focus ??=
        control.dataset.setting ?? control.dataset.action ?? control.id;
    }
    if (menuOpen && root.querySelector("details"))
      root.querySelector("details")!.open = true;
    if (focus) {
      const next = Array.from(
        root.querySelectorAll<HTMLElement>("[data-focus]"),
      ).find((el) => el.dataset.focus === focus);
      next?.focus();
      if (selection !== null && next?.tagName === "INPUT")
        (next as HTMLInputElement).setSelectionRange(selection, selection);
    }
    for (const placeholder of root.querySelectorAll<HTMLElement>(
      "[data-avatar]",
    )) {
      const login = placeholder.dataset.avatar!;
      if (!avatars.has(login))
        avatars.set(
          login,
          invoke<string | null>("get_avatar", { login }).catch(() => {
            avatars.delete(login);
            return null;
          }),
        );
      void avatars.get(login)!.then((src) => {
        if (!src || !placeholder.isConnected || disposed) return;
        const image = document.createElement("img");
        image.className = "avatar";
        image.alt = "";
        image.src = src;
        placeholder.replaceWith(image);
      });
    }
  }
  const alert = () =>
    `<p id="error" class="error" role="alert" ${errorMessage ? "" : "hidden"}>${escape(errorMessage)}</p>`;
  function menu(board: Board) {
    return `<details class="menu"><summary aria-label="More options" data-focus="menu">⋯</summary><div class="menu-items">
      <button data-action="refresh" data-focus="refresh">Refresh <small>${age(board.last_updated)}</small></button>
      <button data-action="people">People…</button><button data-action="about">About Committed</button><hr>
      <label><input type="checkbox" data-setting="notifications" ${settings.notifications ? "checked" : ""}> Leaderboard Notifications</label>
      <label><input type="checkbox" data-setting="launch_at_login" ${desktop.launch_at_login ? "checked" : ""}> Launch at Login</label>
      <label><input type="checkbox" data-setting="automatic_updates" ${settings.automatic_updates ? "checked" : ""}> Automatic Updates</label>
      <button data-action="check-update">Check for Updates…</button><hr>
      <button data-action="disconnect">Disconnect GitHub</button><button data-action="quit">Quit</button>
    </div></details>`;
  }
  async function load() {
    const revision = ++loadRevision;
    const [currentSettings, desktopSettings, board, update] = await Promise.all(
      [
        invoke<Settings>("get_settings"),
        invoke<DesktopSettings>("get_desktop_settings"),
        invoke<Board>("get_board", { window: selected }),
        invoke<{ message: string; ready: boolean } | null>("get_update_status"),
      ],
    );
    if (disposed || revision !== loadRevision) return;
    settings = currentSettings;
    desktop = desktopSettings;
    if (update) {
      status = update.message;
      updateReady = update.ready;
    }
    if (view === "about") {
      replace(
        `<article class="about"><img class="app-icon" src="${appIcon}" alt="" /><h1>Committed</h1><p>A friendly GitHub leaderboard, one click from your tray.</p><p class="muted">Version ${escape(desktop.version)}</p><h2>What counts?</h2><p>Contributions are the green squares on each person’s public GitHub contribution graph. Today, 7 days, and 30 days include today in your local time zone.</p><h2>Private contributions</h2><p>Private activity counts only when that person enables <strong>Contribution settings → Private contributions</strong> on their GitHub profile.</p><p>Connecting requests read-only profile and organization access. Committed never requests repository access. Your token stays in Windows Credential Manager.</p><button data-action="contributions">Open GitHub profile settings</button>${alert()}</article>`,
      );
    } else if (view === "people") {
      const people = await invoke<PersonVisibility[]>("list_people", {
        search,
        filter,
      });
      if (disposed || revision !== loadRevision) return;
      replace(`<header><h1>People</h1><small>${age(board.people_updated)}</small></header><p class="muted">Your follows and organization members. Visibility changes only this PC.</p>
        <label class="search-label">Search People<input type="search" placeholder="Name or username" value="${escape(search)}" data-focus="search" id="search"></label>
        <label class="filter-label">Source<select id="filter" data-focus="filter"><option value="all">All</option><option value="following" ${filter === "following" ? "selected" : ""}>Following</option><option value="organizations" ${filter === "organizations" ? "selected" : ""}>Organizations</option></select></label>
        ${board.people_error ? `<p class="error" role="status">${escape(board.people_error)}</p>` : ""}
        <ul class="people-list">${people.map(({ person, hidden, is_you }) => `<li>${avatar(person)}<span class="identity"><strong>${escape(name(person))}</strong><small>@${escape(person.login)} ${is_you ? "· you" : ""}</small></span><button class="visibility" ${is_you ? "disabled" : ""} data-person="${escape(person.login)}" data-hidden="${!hidden}" data-focus="person-${escape(person.login)}" aria-label="${hidden ? "Show" : "Hide"} ${escape(name(person))}" aria-pressed="${!hidden}"><span aria-hidden="true">${hidden ? "◌" : "◉"}</span> ${hidden ? "Show" : "Hide"}</button></li>`).join("")}</ul>
        ${people.length ? "" : '<p class="muted">No people match this search.</p>'}${alert()}`);
    } else if (view === "person") {
      const next = await invoke<PersonView | null>("get_person");
      if (disposed || revision !== loadRevision) return;
      // Stay on a picked day across refreshes; otherwise follow today, including past midnight.
      const days = next?.history?.this_month.length ?? 0;
      const onToday =
        selectedBar === (personView?.history?.this_month.length ?? 0);
      if (next?.login !== personView?.login || onToday || selectedBar > days)
        selectedBar = days;
      personView = next;
      renderPerson();
    } else if (view === "setup") {
      if (!root.querySelector("#connect"))
        replace(
          `<article class="setup"><img class="app-icon" src="${appIcon}" alt="" /><h1>Committed</h1><p>See your standings alongside your organization members and people you follow. Your list updates automatically.</p><div id="device" role="status" aria-live="polite"></div><button class="primary" id="connect" data-action="connect">Connect GitHub</button><p class="muted privacy">Read-only access to your profile, who you follow, and your organizations. Committed never sees your code. Your token stays in Windows Credential Manager.</p><button data-action="open-device" id="open-device" hidden>Open GitHub again</button>${alert()}</article>`,
        );
    } else {
      const rows = board.rows;
      const me = rows.find((row) => row.is_you);
      const myStreak = me ? streakText(me.streak) : null;
      const refreshing = board.refreshing;
      const first = !board.rows.some((r) => r.contributions !== null);
      const maxContributions = Math.max(
        1,
        ...rows.map((row) => row.contributions ?? 0),
      );
      const statusText = `${windows.find((w) => w[0] === selected)![1]} · ${refreshing ? (first ? "Fetching the first set of standings" : "Updating Contributions…") : board.error ? "Refresh finished with errors." : age(board.last_updated)}`;
      replace(`<header><h1>${brandMark} Committed</h1>${menu(board)}</header><div class="board-content">
        ${me ? `<section class="summary">${avatar(me)}<div><strong>${escape(name(me))}</strong><small>@${escape(me.login)} · you${myStreak ? ` · <span class="streak" role="img" aria-label="${streakSpoken(myStreak)}">🔥 ${myStreak}</span>` : ""}</small></div><div class="summary-count">${count(me.contributions)}<small>Contributions</small></div></section>` : "<p>Connect GitHub to load your board.</p>"}
        <div class="windows" role="radiogroup" aria-label="Time range">${windows.map(([value, label]) => `<button role="radio" aria-checked="${selected === value}" tabindex="${selected === value ? 0 : -1}" data-window="${value}" data-focus="window-${value}">${label}</button>`).join("")}</div>
        <p class="status">${statusText}</p>
        <div class="tracking"><small>Tracking ${rows.length} people</small><button data-action="people">People…</button></div>
        <ol class="standings ${refreshing && !first ? "refreshing" : ""}" aria-label="Leaderboard" aria-busy="${refreshing}">${rows
          .map((row) => {
            const streak = streakText(row.streak);
            const spoken = `Rank ${row.rank}, ${name(row)}, ${row.contributions === null ? "Contributions unavailable" : `${row.contributions} Contributions`}${streak ? `, ${streakSpoken(streak)}` : ""}${row.is_you ? ", you" : ""}${row.burst ? `, trolling: ${trolling(row.burst)}` : ""}`;
            const shade = Math.min(
              1,
              (row.contributions ?? 0) / maxContributions,
            );
            const squareColor = `rgb(${Math.round(156 - 110 * shade)}, ${Math.round(232 - 71 * shade)}, ${Math.round(168 - 102 * shade)})`;
            return `<li class="${row.is_you ? "you" : ""}"><button class="standing" data-open-person="${escape(row.login)}" data-focus="row-${escape(row.login)}" aria-label="${escape(spoken)}"><span class="rank">#${row.rank}</span>${avatar(row)}<span class="identity"><strong title="${escape(name(row))}">${escape(row.login)}${row.is_you ? ' <span class="badge">you</span>' : ""}</strong>${row.status === "failed" ? "<small>Refresh failed</small>" : ""}</span>${row.movement ? `<span class="movement ${row.movement > 0 ? "up" : "down"}" aria-label="Moved ${row.movement > 0 ? "up" : "down"} ${Math.abs(row.movement)}">${row.movement > 0 ? "↑" : "↓"}${Math.abs(row.movement)}</span>` : ""}${streak ? `<span class="streak" aria-hidden="true">🔥 ${streak}</span>` : ""}<strong class="contributions${row.burst ? " troll" : ""}">${count(row.contributions)}</strong>${row.burst ? `<span class="troll-face" style="--troll: url('${trollFace}')" title="${escape(`Problem? ${trolling(row.burst)}.`)}" aria-hidden="true"></span>` : `<svg class="contribution-squares" viewBox="0 0 12 12" fill="${squareColor}" aria-hidden="true" ${row.contributions === null ? 'style="visibility:hidden"' : ""}><path d="M0 0h5v5H0zM7 0h5v5H7zM0 7h5v5H7zM7 7h5v5H7z" /></svg>`}</button></li>`;
          })
          .join("")}</ol>
        ${first && !refreshing ? '<p class="muted">Fetching the first set of standings. Use Refresh to retry if GitHub is unavailable.</p>' : ""}
        ${board.error ? `<p class="error">${escape(board.error)}</p>` : ""}
        <footer><small>${board.people_error ? escape(board.people_error) : `People · ${age(board.people_updated)}`}</small>${board.people_error ? '<button data-action="refresh">Retry</button>' : ""}</footer>
        ${settings.private_tip_dismissed ? "" : '<aside class="tip"><p>Private contributions count when each person enables them on their GitHub profile.</p><button data-action="dismiss-tip" aria-label="Dismiss private contributions tip">×</button></aside>'}
        <p id="update-status" role="status">${escape(status)}</p><button id="install-update" data-action="install-update" ${updateReady ? "" : "hidden"}>Restart to update</button>${alert()}</div>`);
    }
    if (view === "board") {
      const message = root.querySelector(".status")?.textContent ?? "";
      if (announcer.textContent !== message) announcer.textContent = message;
    }
  }
  function renderPerson() {
    replace(
      `<div class="person">${personView ? personHtml(personView, selectedBar) : '<p class="muted">Pick someone on the board to see their month.</p>'}${alert()}</div>`,
    );
  }
  function selectDay(day: number) {
    const days = personView?.history?.this_month.length ?? 0;
    if (!days) return;
    selectedBar = Math.min(days, Math.max(1, day));
    renderPerson();
    root.querySelector<SVGElement>(`[data-day="${selectedBar}"]`)?.focus();
  }
  async function connect() {
    const button = root.querySelector<HTMLButtonElement>("#connect")!;
    button.disabled = true;
    try {
      const prompt = await invoke<{ user_code: string; interval: number }>(
        "start_connect",
      );
      const device = root.querySelector("#device")!;
      device.innerHTML = `<p>Enter this code on GitHub:</p><strong class="device-code">${escape(prompt.user_code)}</strong><p id="poll-status">Waiting for you to approve access…</p>`;
      root.querySelector<HTMLButtonElement>("#open-device")!.hidden = false;
      await act("open_github", { page: "device" });
      const poll = async () => {
        try {
          const result = await invoke<string>("poll_connect");
          if (disposed) return;
          if (result === "connected") {
            button.disabled = false;
            device.textContent = "Connected. Your board is ready.";
            return;
          }
          root.querySelector("#poll-status")!.textContent =
            result === "slowDown"
              ? "GitHub asked us to wait a little longer. Your code is still active."
              : "Waiting for you to approve access…";
          pollTimer = setTimeout(poll, 1000);
        } catch (error) {
          button.disabled = false;
          showError(String(error));
        }
      };
      pollTimer = setTimeout(poll, Math.max(1, prompt.interval) * 1000);
    } catch (error) {
      button.disabled = false;
      showError(String(error));
    }
  }
  const click = async (event: Event) => {
    const day = (event.target as Element).closest<SVGElement>("[data-day]");
    if (day) {
      selectDay(Number(day.dataset.day));
      return;
    }
    const target = (event.target as HTMLElement).closest<HTMLElement>("button");
    if (!target) return;
    if (target.dataset.window) {
      selected = target.dataset.window as Window;
      await act("select_window", { window: selected });
      await load();
      await act("request_refresh", { reason: "windowChanged" });
      root.querySelector<HTMLElement>(`[data-window="${selected}"]`)?.focus();
      return;
    }
    if (target.dataset.openPerson) {
      await act("open_person", { login: target.dataset.openPerson });
      return;
    }
    if (target.dataset.person) {
      await act("set_hidden", {
        login: target.dataset.person,
        hidden: target.dataset.hidden === "true",
      });
      await load();
      return;
    }
    switch (target.dataset.action) {
      case "connect":
        await connect();
        break;
      case "open-device":
        await act("open_github", { page: "device" });
        break;
      case "contributions":
        await act("open_github", { page: "contributions" });
        break;
      case "refresh":
        await act("request_refresh", { reason: "manual" });
        break;
      case "github":
        await act("open_profile", { login: target.dataset.login });
        break;
      case "people":
      case "about":
        await act("open_window", { label: target.dataset.action });
        break;
      case "disconnect":
        await act("disconnect");
        break;
      case "quit":
        await act("quit");
        break;
      case "dismiss-tip":
        await act("set_setting", {
          setting: "private_tip_dismissed",
          enabled: true,
        });
        await load();
        break;
      case "check-update":
        status = "Checking for updates…";
        await load();
        await act("check_updates", { manual: true });
        break;
      case "install-update":
        await act("install_update");
        break;
    }
  };
  const change = async (event: Event) => {
    const input = event.target as HTMLInputElement;
    if (input.dataset.setting === "launch_at_login")
      await act("set_launch_at_login", { enabled: input.checked });
    else if (input.dataset.setting)
      await act("set_setting", {
        setting: input.dataset.setting,
        enabled: input.checked,
      });
    else if (input.id === "filter") filter = input.value;
    await load();
  };
  const input = (event: Event) => {
    if ((event.target as HTMLElement).id === "search") {
      search = (event.target as HTMLInputElement).value;
      void load().catch((error) => showError(String(error)));
    }
  };
  const keydown = (event: KeyboardEvent) => {
    const bar = (event.target as Element).closest<SVGElement>("[data-day]");
    if (bar && ["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) {
      event.preventDefault();
      const day = Number(bar.dataset.day);
      selectDay(
        event.key === "Home"
          ? 1
          : event.key === "End"
            ? Infinity
            : day + (event.key === "ArrowRight" ? 1 : -1),
      );
      return;
    }
    const row = (event.target as HTMLElement).closest<HTMLButtonElement>(
      ".standing",
    );
    if (row && ["ArrowUp", "ArrowDown", "Home", "End"].includes(event.key)) {
      event.preventDefault();
      const rows = Array.from(
        root.querySelectorAll<HTMLButtonElement>(".standing"),
      );
      const index = rows.indexOf(row);
      const next =
        event.key === "Home"
          ? 0
          : event.key === "End"
            ? rows.length - 1
            : (index + (event.key === "ArrowDown" ? 1 : rows.length - 1)) %
              rows.length;
      rows[next]?.focus();
    }
    const radio = (event.target as HTMLElement).closest<HTMLElement>(
      "[data-window]",
    );
    if (
      radio &&
      ["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)
    ) {
      event.preventDefault();
      const index = windows.findIndex((w) => w[0] === radio.dataset.window);
      const next =
        event.key === "Home"
          ? 0
          : event.key === "End"
            ? windows.length - 1
            : (index + (event.key === "ArrowRight" ? 1 : windows.length - 1)) %
              windows.length;
      root
        .querySelector<HTMLButtonElement>(`[data-window="${windows[next][0]}"]`)
        ?.click();
    }
    if (event.key === "Escape") {
      const menu = root.querySelector<HTMLDetailsElement>("details[open]");
      if (menu) {
        menu.open = false;
        menu.querySelector("summary")?.focus();
      } else if (view === "board") void act("hide_board");
    }
  };
  const onClick = (event: Event) => {
    void click(event).catch((error) => showError(String(error)));
  };
  const onChange = (event: Event) => {
    void change(event).catch((error) => showError(String(error)));
  };
  root.addEventListener("click", onClick);
  root.addEventListener("change", onChange);
  root.addEventListener("input", input);
  root.addEventListener("keydown", keydown);
  const unlisten = await listen("board-changed", () => {
    void load().catch((error) => showError(String(error)));
  });
  const unlistenError = await listen<string>("app-error", (event) =>
    showError(event.payload),
  );
  const unlistenUpdate = await listen<{ message: string; ready: boolean }>(
    "update-status",
    (event) => {
      status = event.payload.message;
      updateReady = event.payload.ready;
      const label = root.querySelector("#update-status");
      if (label) label.textContent = status;
      const install = root.querySelector<HTMLButtonElement>("#install-update");
      if (install) install.hidden = !event.payload.ready;
    },
  );
  await load();
  return () => {
    disposed = true;
    clearTimeout(pollTimer);
    unlisten();
    unlistenError();
    unlistenUpdate();
    announcer.remove();
    root.removeEventListener("click", onClick);
    root.removeEventListener("change", onChange);
    root.removeEventListener("input", input);
    root.removeEventListener("keydown", keydown);
  };
}
