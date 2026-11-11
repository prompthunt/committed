"use client";

import { useEffect, useMemo, useState } from "react";
import {
  GitHubLookupError,
  KRAKEN_URL,
  loadSettings,
  localTimeZone,
  lookUpPeople,
  MAX_RIVALS,
  normalizeLogin,
  saveSettings,
  settingsLink,
  WINDOW_LABELS,
  type KrakenSettings,
  type KrakenWindow,
  type Person,
} from "@/lib/kraken";
import { KrakenFace, type Shape } from "./KrakenFace";
import { useBoard, useNow } from "./useBoard";

const PREVIEWS: { label: string; size: number; shape: Shape }[] = [
  { label: "Kraken Elite · 640", size: 640, shape: "circle" },
  { label: "Kraken Z · 320", size: 320, shape: "circle" },
  { label: "Kraken · 240", size: 240, shape: "square" },
];

/** The setup page: CAM's Configuration Browser, or any browser. Saves as you go. */
export function KrakenSetup() {
  const [settings, setSettings] = useState<KrakenSettings | null>(() => loadSettings());
  const [username, setUsername] = useState(settings?.login ?? "");
  const [loading, setLoading] = useState(false);
  const [lookupError, setLookupError] = useState<string | null>(null);
  const [filter, setFilter] = useState("");
  const [extra, setExtra] = useState("");
  const [preview, setPreview] = useState(1);
  const [copied, setCopied] = useState(false);
  const { state, error } = useBoard(settings);
  const now = useNow();

  useEffect(() => {
    if (settings) saveSettings(settings);
  }, [settings]);

  const update = (change: Partial<KrakenSettings>) => setSettings((current) => (current ? { ...current, ...change } : current));

  async function load(event: React.FormEvent) {
    event.preventDefault();
    setLoading(true);
    setLookupError(null);
    try {
      const { self, following } = await lookUpPeople(username);
      const previous = settings?.login === self.login ? settings : null;
      const extras = previous?.people.filter((person) => !following.some((f) => f.login === person.login)) ?? [];
      const people = [...following, ...extras].filter((person) => person.login !== self.login);
      // Keep earlier picks for the same account; a new account starts with everyone it follows.
      const competitors = previous
        ? previous.competitors.filter((login) => people.some((person) => person.login === login))
        : people.slice(0, MAX_RIVALS).map((person) => person.login);
      setSettings({
        login: self.login,
        avatar: self.avatar,
        people,
        competitors,
        window: previous?.window ?? "daily",
        timeZone: localTimeZone(),
      });
      setUsername(self.login);
    } catch (caught) {
      setLookupError(caught instanceof GitHubLookupError ? caught.message : "Couldn’t reach GitHub. Try again.");
    } finally {
      setLoading(false);
    }
  }

  function toggle(login: string) {
    if (!settings) return;
    const on = settings.competitors.includes(login);
    if (!on && settings.competitors.length >= MAX_RIVALS) return;
    update({ competitors: on ? settings.competitors.filter((entry) => entry !== login) : [...settings.competitors, login] });
  }

  function addPerson(event: React.FormEvent) {
    event.preventDefault();
    if (!settings) return;
    const login = normalizeLogin(extra);
    if (!login || login === settings.login) return;
    const people: Person[] = settings.people.some((person) => person.login === login)
      ? settings.people
      : [...settings.people, { login, avatar: `https://github.com/${login}.png?size=64` }];
    const competitors =
      settings.competitors.includes(login) || settings.competitors.length >= MAX_RIVALS
        ? settings.competitors
        : [...settings.competitors, login];
    update({ people, competitors });
    setExtra("");
  }

  const visible = useMemo(
    () =>
      (settings?.people ?? [])
        .filter((person) => person.login.includes(filter.trim().toLowerCase()))
        .sort((a, b) => a.login.localeCompare(b.login)),
    [settings?.people, filter],
  );

  const shown = PREVIEWS[preview]!;
  const previewScale = Math.min(1, 320 / shown.size);
  const message = !settings ? "Set up your board in NZXT CAM" : !state && error ? "Can’t reach Committed right now" : null;

  return (
    <main className="mx-auto max-w-5xl px-4 py-10 sm:px-8 sm:py-14">
      <p className="text-sm font-semibold uppercase tracking-[0.12em] text-lime">Committed for NZXT Kraken</p>
      <h1 className="mt-3 text-3xl font-extrabold tracking-tight sm:text-4xl">Your rank on your Kraken’s screen</h1>
      <p className="mt-3 max-w-2xl text-soft">
        Pick who you’re racing, and your Kraken LCD shows where you stand on today’s, this week’s or this month’s GitHub
        contributions. It refreshes every minute.
      </p>

      <div className="mt-10 grid gap-10 lg:grid-cols-[minmax(0,1fr)_340px]">
        <div className="min-w-0 space-y-8">
          <section>
            <h2 className="text-lg font-bold">1. Your GitHub username</h2>
            <form onSubmit={load} className="mt-3 flex flex-wrap gap-2">
              <input
                value={username}
                onChange={(event) => setUsername(event.target.value)}
                placeholder="octocat"
                autoComplete="username"
                spellCheck={false}
                aria-label="GitHub username"
                className="h-11 min-w-0 flex-1 rounded-lg border border-white/15 bg-tile px-3 text-white placeholder:text-faint focus:border-lime focus:outline-none"
              />
              <button
                type="submit"
                disabled={loading || !username.trim()}
                className="h-11 rounded-lg bg-lime px-4 font-semibold text-on-lime disabled:opacity-50"
              >
                {loading ? "Loading…" : settings ? "Reload people" : "Load people you follow"}
              </button>
            </form>
            {lookupError && <p className="mt-2 text-sm text-[#ff8a7a]">{lookupError}</p>}
          </section>

          {settings && (
            <>
              <section>
                <h2 className="text-lg font-bold">2. Window</h2>
                <div className="mt-3 inline-flex rounded-lg border border-white/15 bg-tile p-1" role="radiogroup" aria-label="Window">
                  {(Object.keys(WINDOW_LABELS) as KrakenWindow[]).map((window) => (
                    <button
                      key={window}
                      type="button"
                      role="radio"
                      aria-checked={settings.window === window}
                      onClick={() => update({ window })}
                      className={`h-9 rounded-md px-4 text-sm font-semibold ${settings.window === window ? "bg-lime text-on-lime" : "text-soft"}`}
                    >
                      {WINDOW_LABELS[window]}
                    </button>
                  ))}
                </div>
              </section>

              <section>
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <h2 className="text-lg font-bold">3. Who you’re racing</h2>
                  <p className="text-sm text-muted">
                    {settings.competitors.length} of {settings.people.length} on your board
                    {settings.competitors.length >= MAX_RIVALS && ` (${MAX_RIVALS} at most)`}
                  </p>
                </div>
                <p className="mt-1 text-sm text-muted">
                  Everyone you follow on GitHub. Uncheck anyone you don’t want on your board, or add someone you don’t follow.
                </p>
                <div className="mt-3 flex flex-wrap gap-2">
                  <input
                    value={filter}
                    onChange={(event) => setFilter(event.target.value)}
                    placeholder="Search"
                    aria-label="Search people"
                    className="h-10 min-w-0 flex-1 rounded-lg border border-white/15 bg-tile px-3 text-sm text-white placeholder:text-faint focus:border-lime focus:outline-none"
                  />
                  <button type="button" onClick={() => update({ competitors: settings.people.slice(0, MAX_RIVALS).map((p) => p.login) })} className="h-10 rounded-lg border border-white/15 px-3 text-sm text-soft">
                    All
                  </button>
                  <button type="button" onClick={() => update({ competitors: [] })} className="h-10 rounded-lg border border-white/15 px-3 text-sm text-soft">
                    None
                  </button>
                </div>
                <ul className="mt-3 max-h-80 overflow-y-auto rounded-lg border border-white/10 bg-tile">
                  {visible.length === 0 && (
                    <li className="px-3 py-4 text-sm text-muted">{settings.people.length === 0 ? "You don’t follow anyone yet. Add people below." : "No matches."}</li>
                  )}
                  {visible.map((person) => (
                    <li key={person.login} className="border-b border-white/5 last:border-0">
                      <label className="flex cursor-pointer items-center gap-3 px-3 py-2">
                        <input
                          type="checkbox"
                          checked={settings.competitors.includes(person.login)}
                          onChange={() => toggle(person.login)}
                          className="size-4 accent-[var(--color-lime)]"
                        />
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img src={person.avatar} alt="" width={24} height={24} className="size-6 rounded-full bg-sq-0" loading="lazy" />
                        <span className="truncate text-sm">{person.login}</span>
                      </label>
                    </li>
                  ))}
                </ul>
                <form onSubmit={addPerson} className="mt-3 flex gap-2">
                  <input
                    value={extra}
                    onChange={(event) => setExtra(event.target.value)}
                    placeholder="Add a GitHub username"
                    aria-label="Add a GitHub username"
                    spellCheck={false}
                    className="h-10 min-w-0 flex-1 rounded-lg border border-white/15 bg-tile px-3 text-sm text-white placeholder:text-faint focus:border-lime focus:outline-none"
                  />
                  <button type="submit" disabled={!normalizeLogin(extra)} className="h-10 rounded-lg border border-white/15 px-3 text-sm font-semibold disabled:opacity-40">
                    Add
                  </button>
                </form>
              </section>
            </>
          )}

          <section className="rounded-xl border border-white/10 bg-tile p-5">
            <h2 className="text-lg font-bold">Put it on your Kraken</h2>
            <ol className="mt-3 list-decimal space-y-1.5 pl-5 text-sm text-soft">
              <li>In NZXT CAM, open your Kraken and choose <strong className="text-white">Lighting</strong> (or <strong className="text-white">LCD</strong>).</li>
              <li>Set the mode to <strong className="text-white">Web Integration</strong>, then <strong className="text-white">Edit</strong> the custom URL.</li>
              <li>
                Enter <code className="rounded bg-ink px-1.5 py-0.5 text-lime">{KRAKEN_URL}</code> and press the arrow.
              </li>
              <li>Fill in the steps above on the setup page CAM shows. Your Kraken updates as you go.</li>
            </ol>
            {settings && (
              <div className="mt-4 text-sm text-muted">
                <p>Set this up in a regular browser instead? Paste this link into CAM. It carries your board with it:</p>
                <div className="mt-2 flex gap-2">
                  <input readOnly value={settingsLink(settings)} aria-label="Link with your board" onFocus={(event) => event.currentTarget.select()} className="h-10 min-w-0 flex-1 rounded-lg border border-white/15 bg-ink px-3 font-mono text-xs text-soft" />
                  <button
                    type="button"
                    onClick={() => {
                      void navigator.clipboard?.writeText(settingsLink(settings)).then(() => {
                        setCopied(true);
                        window.setTimeout(() => setCopied(false), 1500);
                      });
                    }}
                    className="h-10 rounded-lg border border-white/15 px-3 font-semibold text-white"
                  >
                    {copied ? "Copied" : "Copy"}
                  </button>
                </div>
              </div>
            )}
          </section>
        </div>

        <aside className="lg:sticky lg:top-10 lg:self-start">
          <div className="flex flex-col items-center gap-4">
            <div className="flex size-[320px] items-center justify-center">
              <div style={{ transform: `scale(${previewScale})` }}>
                <KrakenFace size={shown.size} shape={shown.shape} window={settings?.window ?? "daily"} state={message ? null : state} message={message} now={now} />
              </div>
            </div>
            <div className="flex flex-wrap justify-center gap-1" role="radiogroup" aria-label="Preview screen">
              {PREVIEWS.map((entry, index) => (
                <button
                  key={entry.label}
                  type="button"
                  role="radio"
                  aria-checked={preview === index}
                  onClick={() => setPreview(index)}
                  className={`rounded-md px-2.5 py-1 text-xs font-semibold ${preview === index ? "bg-white/10 text-white" : "text-muted"}`}
                >
                  {entry.label}
                </button>
              ))}
            </div>
            <p className="max-w-[320px] text-center text-xs text-faint">
              Counts come from public GitHub contribution graphs, the same ones the Committed apps rank. Private contributions count only if that person shows them on their profile.
            </p>
          </div>
        </aside>
      </div>
    </main>
  );
}
