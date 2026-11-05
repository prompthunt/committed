# Committed relay

A small push service that keeps **Live rank** current while the iPhone app is closed. Every 5
minutes it recomputes each registered iPhone's `LiveRankState` from public GitHub contribution
graphs and sends ActivityKit pushes through APNs. Spec: issue #39 ("Live rank: the Committed relay").
This folder is the service; the iPhone app's client is `CommitStandingsiOS/LiveRankRelay.swift` (registration rules in `LiveRankController`, build settings in `docs/distribution.md` → iPhone).

It is a TypeScript Cloudflare Worker with a Cron Trigger (`*/5 * * * *`) and a D1 database.

**Privacy.** The relay receives public GitHub logins only: yours and the ones visible on your board.
It never accepts, stores, or logs a GitHub token. Request bodies are strict, so a body with any
field outside the contract is rejected with `400` and nothing is stored. The install secret is
stored only as a SHA-256 hash. Logs carry a shortened install ID, never push tokens, secrets, or
request bodies (`src/log.ts` is the only logging path). Workers invocation logs are off in
`wrangler.jsonc`, because they record request headers and so the bearer secret.

## Layout

| Path | What it is |
|---|---|
| `src/api.ts` | Device API, auth, validation, rate limiting |
| `src/cron.ts` | The 5-minute update: counts, movement, push decisions, rotation |
| `src/ranking.ts` | Port of `Ranking.order` and the `LiveRankState` derivation |
| `src/parser.ts` | Port of `ContributionsParser` |
| `src/contributions.ts` | Anonymous contributions fetch with a shared 5-minute D1 cache, refresh order |
| `src/apns.ts` | APNs transport interface, `fetch()` transport, response handling |
| `src/auth.ts` | ES256 provider token (WebCrypto), cached under an hour |
| `src/payload.ts` | `start` / `update` / `end` payloads |
| `migrations/` | D1 schema |
| `spike/` | APNs HTTP/2 probe Worker |
| `../shared/fixtures/` | Conformance fixtures, also run by the Mac tests |

## Device API

JSON over HTTPS. Every request sends `Authorization: Bearer <install secret>`: a random secret,
32 to 256 characters, generated on the iPhone and kept in its Keychain. The first `PUT` for an
install ID sets that ID's secret; later requests with a different secret get `401`. Install IDs
are 8 to 64 characters of `[A-Za-z0-9-]` (a UUID).

### `PUT /v1/installations/{id}`

Register, or replace the registration. Send every field every time.

```json
{
  "login": "addisonk",
  "competitors": ["addisonk", "alice", "bob"],
  "window": "daily",
  "timeZone": "America/Los_Angeles",
  "environment": "sandbox",
  "pushToStartToken": "8a3f…"
}
```

- `login`: your GitHub login.
- `competitors`: the **visible** logins in board order (`StandingsStore.visibleCompetitors`),
  **including yourself**. Order breaks ties, so send it exactly as the board orders it (the app
  puts you first, then everyone else sorted). Logins are normalized like `UsernameNormalization`;
  duplicates are dropped. At most 1,000 entries, and it must contain `login`.
- `window`: `daily`, `weekly`, or `monthly` (the `ContributionWindow` raw value).
- `timeZone`: an IANA zone. Today, 7 days, and 30 days are summed for this zone's calendar day.
- `environment`: `sandbox` (development builds) or `production` (TestFlight and App Store).
- `pushToStartToken`: hex, or `null`/absent if iOS hasn't issued one.

Replies `204`. Changing `window`, `timeZone`, `login`, or `competitors` resets today's movement
baseline. Changing `window` also makes the next run push to the current activity.

### `PUT /v1/installations/{id}/activity`

```json
{ "activityId": "…", "pushToken": "c41d…", "startedAt": 1793838000 }
```

Report the current Live Activity and its update push token, including activities the relay
started with push-to-start. `startedAt` is optional: the Unix seconds the app started the
activity, sent only for activities the app started (older apps omit it). A start time later
than now counts as now.

A new `activityId` starts the 7.5-hour rotation clock at the activity's start, not at the
report: `startedAt` when given; for an activity the relay started, the send time of its
push-to-start; otherwise now. The same `activityId` with a new token keeps the activity's age.
Replies `204`; `400` for a bad `startedAt`; `404` for an unknown installation.

### `DELETE /v1/installations/{id}`

Ends the current activity at once (an `end` push with a past dismissal date), then deletes the
registration. Replies `204`, including for an unknown installation. Never rate limited.

### Errors and limits

`400` invalid body (including unknown fields), `401` missing, short, or wrong secret, `404`
unknown route or installation, `405` wrong method, `409` concurrent update (retry), `429` more
than 30 writes in 10 minutes for one installation (with `Retry-After`).

## LiveRankState derivation

`deriveLiveRankState` in `src/ranking.ts` is the contract shared with the iPhone app.
`shared/fixtures/ranking-conformance.json` pins every rule below, and the Swift side runs the
same file.

Inputs: the visible competitors in board order (self included), standings (`login →
{contributions, window, lastUpdated}`), the Window, today's rank deltas (`login → places moved`),
and `now`.

- **Order** is `Ranking.order`: contributions descending; no data sorts last, below a real `0`;
  ties keep competitor order. A standing for a different Window counts as no data. Standings for
  logins outside the visible list are ignored.
- **No data** means the login has no standing. The relay never produces the Mac's
  failed-with-zero row (`state: .failed`, `lastUpdated: .distantPast`). On the device, drop those
  rows before deriving, or `Ranking.order` will rank them as `0`.
- **`competitorCount`**: every visible competitor including you, with or without data.
- **`contributions`**: your count for the Window, or `nil` when you have no data.
- **`rank`**: your position in the order, or `nil` when you have no data ("no data yet") or no
  one else is visible ("no visible rivals"). When you have data and no rival does, you are `#1`.
  This deliberately differs from `MenuBarLabel.currentRank`, which shows a rank for a self row
  with no data.
- **`above`**: the entry directly before you in the order. It always has data when you do, and
  it can be tied with you (the gap to pass is then 1).
- **`below`**: the entry directly after you, or `nil` when it has no data.
- With `rank == nil`, `above` and `below` are `nil` too.
- **`movementToday`**: your delta from the input, only when the Window is `daily` and you have a
  rank; otherwise `0`.
- **`updatedAt`**: the oldest `lastUpdated` among the counts the state shows (yours, `above`,
  and `below`), rounded down to whole seconds; `now` (rounded down) when it shows none. A stale
  count of yours, or of a neighbor, never looks fresh because someone else's refreshed.
- **Encoding.** Dates are integer Unix seconds. Payloads omit `nil` keys, as Swift's synthesized
  `Encodable` does; the fixture writes them as `null`. Decoders treat a missing key and `null`
  alike.

**Today's movement baseline** is an input to the derivation, computed outside it, as
`RefreshCoordinator.updateDailyRankDeltas` does. The first run of an installation's local day
records each ranked login's position. Only logins with data count. Later runs report
`baseline − current`. The baseline resets at local midnight, and when the board, Window, or time
zone changes. Outside Today no baseline is kept.

## Update rules

Each cron run, for every installation:

1. **Counts.** Every login on any board is read from `contribution_cache`. Entries 5 minutes old
   or older are due a refetch, in this order: first each board's own login and the people
   directly above and below it (by the cached counts), so the numbers Live rank shows stay
   fresh; then everyone else, stalest first, never-fetched logins before cached ones. A run
   fetches at most its fetch budget ("Limits to know"); the rest keep their cached counts until a later
   run. A failed fetch keeps the last cached counts. A login that was never fetched
   successfully has no data. `lastUpdated` is the time of the successful fetch.
2. **State.** Sum the Window for the installation's local calendar day, apply the movement
   baseline, and derive `LiveRankState`.
3. **Rotation** (iOS ends a Live Activity after 8 hours):
   - Activity 7.5 hours old: send `end` with a dismissal date in the past to its token, then
     push-to-start a fresh activity with the push-to-start token.
   - No activity but a push-to-start token: start one once 7.5 hours have passed since the last
     start or report. A new installation starts that clock at registration, because the app
     starts the first activity itself. This also covers a user who dismissed it: the relay waits
     instead of fighting them every 5 minutes.
   - Today resets in place at local midnight, with no new activity.
4. **Update** an existing activity only when the state changed, ignoring `updatedAt`. Otherwise
   send a heartbeat once the last stale date is 10 minutes away, but only if the data advanced
   (when GitHub fetches fail, the activity is left to go stale).
   - `apns-priority: 10` only when `rank` changed from the last delivered state, otherwise `5`.
     The first push to a newly reported activity is `5`.
   - `stale-date` = `updatedAt` + 20 minutes, on every `update` and `start`.
   - `end` (rotation and unregister) uses priority `5`: it is never urgent, and the spec keeps
     `10` for rank changes.
   - Push-to-start (`start`) uses priority `10`. Apple's "Starting and updating Live Activities
     with ActivityKit push notifications" allows `5` or `10` for a start, and describes `10` as
     delivered immediately and `5` as delivered opportunistically. A late start leaves no Live
     rank on screen until it lands, and starts are rare (one per 7.5 hours), so `10` is worth
     its share of the budget. Because the `end` goes at `5`, it can land after the new
     activity starts, so two activities may show together for a moment. The app ends the
     extra one the next time it syncs, and iOS ends the old one at 8 hours anyway.
5. **Responses.** `410` (any reason) or `400` with `BadDeviceToken` or `DeviceTokenNotForTopic`
   drops that token: an activity token forgets the activity, a push-to-start token stops
   restarts. `403 ExpiredProviderToken`/`InvalidProviderToken` drops the cached provider token.
   Anything else is retried on the next run.

Cron writes are guarded by a row `revision`, so a device write that lands mid-run is never
overwritten. The run's outcome is re-applied to the fresh row instead.

### APNs requests

`POST https://api.sandbox.push.apple.com/3/device/<token>` (or `api.push.apple.com` for
`production`) with:

- `authorization: bearer <ES256 JWT>`; header `{alg: ES256, kid: APNS_KEY_ID}`, claims
  `{iss: APNS_TEAM_ID, iat}`, reused for 50 minutes (Apple: refresh no more than every 20 and no
  less than every 60 minutes), cached in D1 so isolates share it.
- `apns-push-type: liveactivity`
- `apns-topic: <APNS_BUNDLE_ID>.push-type.liveactivity`
- `apns-priority: 5 | 10`

```json
{ "aps": { "timestamp": 1793838000, "event": "update",
           "content-state": { "window": "daily", "rank": 2, "competitorCount": 3, "contributions": 5,
                              "above": { "login": "alice", "contributions": 9 },
                              "below": { "login": "bob", "contributions": 3 },
                              "movementToday": 0, "updatedAt": 1793838000 },
           "stale-date": 1793839200 } }
```

`start` adds `"attributes-type": "LiveRankAttributes"`, `"attributes": {"selfLogin": …}`,
`"input-push-token": 1`, and the `alert` Apple requires for push-to-start. `end` carries the
final state and a past `dismissal-date`. Payload rules follow Apple's "Starting and updating Live
Activities with ActivityKit push notifications" and "Handling notification responses from APNs".

## APNs HTTP/2 spike

APNs accepts only HTTP/2. The question was whether a Worker's outbound `fetch()` reaches it over
HTTP/2.

**The probe.** An unauthenticated `POST` to `https://api.sandbox.push.apple.com/3/device/00`
answers `403 {"reason":"MissingProviderToken"}` over HTTP/2 and drops the connection over
HTTP/1.1. The answer shows the protocol without an APNs key. `spike/apns-probe.ts` runs that
probe from a Worker.

| Check | Result |
|---|---|
| `curl --http2` to the probe URL (macOS, 2026-11-04) | **Verified**: `HTTP/2 403 {"reason":"MissingProviderToken"}` |
| `curl --http1.1` to the probe URL | **Verified**: connection dropped, no response |
| Probe under local `wrangler dev` (workerd 1.20261103, wrangler 4.157) | **Fails**: `Network connection lost`, APNs's HTTP/1.1 behavior. Local workerd does not reach APNs, so `wrangler dev` can't deliver pushes. This is local workerd, not Cloudflare's edge, and doesn't decide the question. |
| Probe on Cloudflare's edge (`wrangler dev --remote` or a deploy) | **Deferred to #47**: no Cloudflare account was available to this ticket. |
| Cloudflare docs | Silent on the protocol of Worker subrequests to non-Cloudflare hosts. "HTTP/2 to Origin" (on by default) covers proxied zone traffic. A Workers APNs client exists (`@fivesheepco/cloudflare-apns2`), which is circumstantial evidence only. |
| Real Live Activity push to the APNs sandbox | **Deferred to #47**: needs the `.p8` key and a device or simulator token. |

**Chosen runtime: Cloudflare Workers, pending the edge probe.** Run it first:

```bash
cd relay
npx wrangler dev --config spike/wrangler.jsonc --remote
curl -s http://localhost:8787/
```

Pass is `"status": 403` with `MissingProviderToken` in `body`. Then send one real push with the
deployed relay (see Setup) and check the device shows it.

**If the probe fails**, move to a Vercel Node function using `node:http2`, with an external cron
hitting it every 5 minutes. The APNs transport is the `ApnsTransport` interface in
`src/apns.ts`, so that is a transport swap: implement `send()` over a `node:http2` session to
`APNS_HOSTS[environment]`. Everything else stays: API, cron logic, payloads, JWT signing
(WebCrypto exists in Node). D1 would need a replacement store behind `src/store.ts`,
`src/contributions.ts`, and `src/auth.ts`.

## Setup (human ticket #47)

Needs: a Cloudflare account, the App ID with Push Notifications, and an APNs auth key (`.p8`).

```bash
cd relay
npm ci
npx wrangler login
npx wrangler d1 create committed-relay           # copy database_id into wrangler.jsonc
npx wrangler d1 migrations apply committed-relay --remote
npx wrangler secret put APNS_TEAM_ID             # Apple Developer team ID
npx wrangler secret put APNS_KEY_ID              # the .p8 key's Key ID
npx wrangler secret put APNS_PRIVATE_KEY < AuthKey_XXXXXXXXXX.p8
npx wrangler deploy
```

- `APNS_BUNDLE_ID` is a var in `wrangler.jsonc` (`com.addisonk.CommitStandings.iOS`). The topic
  is `<bundle>.push-type.liveactivity`.
- An APNs key works for both environments unless it was created for only one (APNs then answers
  `403 BadEnvironmentKeyIdInToken`). Each installation says which host to use.
- For a staging relay, deploy with another `name` and D1 database (`wrangler deploy --env` or a
  second config) and point Debug builds at it. The app reads the relay base URL from a build
  setting.
- After deploy, run the edge probe above, then register a simulator with a real activity token
  and watch `npx wrangler tail` for `push_delivered`.
- Consider a WAF rate-limiting rule on `/v1/installations/*`. Per-installation limits don't stop
  someone from creating many installations.

### Limits to know

- **Subrequests per run.** Every GitHub fetch and every APNs push is an outbound subrequest,
  and Workers caps them per invocation: 50 on the free plan, 10,000 by default on Workers Paid
  (raise it further with `limits.subrequests` in `wrangler.jsonc`). D1 calls draw on a separate
  pool. Two vars set the relay's share:
  - `SUBREQUEST_LIMIT` (default `"50"`): outbound requests per run. On Workers Paid, set it
    to `"10000"` (or your `limits.subrequests`).
  - `GITHUB_FETCH_BUDGET` (default `"40"`): most GitHub fetches per run. On Workers Paid, set
    it to the number of distinct logins you expect (for example `"5000"`), so every count
    refreshes every run.

  Pushes always come first. Before fetching, a run reserves one subrequest for each
  installation that may get a push (an activity to update, or a push-to-start that is due),
  and two for each rotation (`end` and `start`). It fetches at most
  `min(GITHUB_FETCH_BUDGET, SUBREQUEST_LIMIT − reserve)`. A push that still doesn't fit waits
  for the next run (`push_deferred`); a rotation sends both pushes or neither.

  On the free plan this leaves 50 minus the installation count for fetches. Past about 25
  installations, counts refresh slowly; past 50, pushes queue across runs. Each board's own
  login and neighbors are fetched first, so Live rank stays current longest. Move to Workers
  Paid before that.
- **CPU.** Parsing a contributions page is small, but each installation costs a D1 write per
  change. Large deployments should batch installations across invocations.
- **Budget and heartbeats.** `updatedAt` is the oldest of the counts a state shows. If one of
  them misses a run, `updatedAt` doesn't advance, no heartbeat goes out, and the activity can
  show as stale until that count comes around. Fetching each board's own login and neighbors
  first keeps this rare.
- **GitHub.** Pages are fetched anonymously from Cloudflare IPs. If GitHub rate-limits those,
  counts go stale (the activity shows its refresh age) rather than wrong.

## Develop

```bash
cd relay
npm ci
npm run typecheck
npm test                                   # Vitest inside workerd, fake APNs + fake GitHub
npm run db:migrate:local
npx wrangler dev --test-scheduled          # then: curl "http://localhost:8787/cdn-cgi/handler/scheduled?cron=*/5+*+*+*+*"
```

Locally, `wrangler dev` fetches real GitHub pages and fills the D1 cache, but can't reach APNs
(see the spike). Without the APNs secrets the cron logs `apns_not_configured` and sends nothing.

CI runs `npm run typecheck` and `npm test` in the `relay` job of `.github/workflows/ci.yml`.
