# Committed relay

The Committed relay keeps **Live rank** current while the iPhone app is closed (spec #39,
phase 2; ticket #44). Every 5 minutes it reads public contribution graphs, recomputes each
registered installation's `LiveRankState`, and sends ActivityKit pushes through APNs. Before
iOS's 8-hour limit, it ends the activity and starts a fresh one with push-to-start.

It receives only public GitHub usernames. It never accepts, stores, or logs a GitHub token,
and its logs omit push tokens and install secrets.

- Runtime: TypeScript Cloudflare Worker, D1, Cron Trigger `*/5 * * * *`
- Node 24 for tooling (`.nvmrc`), matching `windows/` and the CI job

## APNs HTTP/2 spike

APNs only speaks HTTP/2. The question was whether a Worker's outbound `fetch` can reach it.
The probe POSTs a Live Activity push to `https://api.sandbox.push.apple.com/3/device/<64 zeros>`
with a garbage bearer token. Over HTTP/2, Apple answers `403 {"reason":"InvalidProviderToken"}`
(or `MissingProviderToken` without a token). An HTTP/1.1-only transport fails at the protocol
level.

Run on 2026-11-04 (`spike/apns-h2-spike.js`):

| Where | Result |
|---|---|
| `curl --http2` from a Mac (control) | `HTTP/2 403 {"reason":"InvalidProviderToken"}` |
| `curl --http1.1` from a Mac (control) | no response: APNs refuses HTTP/1.1 |
| `wrangler dev` (local workerd, wrangler 4.157.0 / workerd 1.20261103) | `fetch` throws `Network connection lost.`, with or without a token |
| Deployed Worker on Cloudflare's edge (2026-11-06, `committed-apns-spike.prompt-hunt.workers.dev`) | **HTTP/2 works.** `403 {"reason":"InvalidProviderToken"}` with a token, `MissingProviderToken` without. The spike Worker was deleted afterwards. |

**What this means:**

- **Local `wrangler dev` cannot reach APNs.** Local workerd's outbound `fetch` is HTTP/1.1.
  Tests and local runs use a fake APNs (`test/support/fakes.ts`); everything else (device
  API, D1, cron via `--test-scheduled`, real GitHub fetches) works locally.
- **The edge works.** A deployed Worker's plain `fetch` reaches APNs over HTTP/2.

**Runtime: Cloudflare Workers, as the spec says.** All APNs I/O sits behind the small
`ApnsSender` interface (`src/apns.ts`), so a transport change wouldn't touch the relay logic.

**Production:** `https://committed-relay.prompt-hunt.workers.dev`, on Prompt Hunt's Cloudflare
account (`account_id` in `wrangler.jsonc`), with D1 `committed-relay`. The iOS Release build's
`COMMITTED_RELAY_URL` points here.

**To re-run the check** (about a minute):

```bash
cd relay
npx wrangler deploy -c spike/wrangler.spike.jsonc
curl https://committed-apns-spike.prompt-hunt.workers.dev/   # {"http2": true, ...} means Workers works
npx wrangler delete -c spike/wrangler.spike.jsonc
```

**If `http2` is false**, follow the spec's fallback:

1. Move `src/` to a Vercel Node function and implement `ApnsSender` with `node:http2`
   (`http2.connect(host).request({":method":"POST", ":path":"/3/device/<token>", ...})`).
2. Replace D1 with a Postgres or SQLite store that has the same `Store` methods.
3. Drive `runCycle()` from an external 5-minute cron (for example a GitHub Actions schedule
   or cron-job.org hitting an authenticated endpoint).
4. Record the switch here.

## Device API

JSON over HTTPS. Every request carries `Authorization: Bearer <install secret>`: a random
secret of 32 to 256 characters that the device generates once and keeps in its Keychain. The
first `PUT` claims the installation ID. The relay stores only the secret's SHA-256 and compares
hashes in constant time. A different secret gets `401`.

Unknown fields are rejected with `400`, so a GitHub token cannot be sent even by mistake.
Logins must be valid GitHub usernames.

### `PUT /v1/installations/{id}`

Registers or updates. `{id}` is 8 to 64 characters of `[A-Za-z0-9-]`; a UUID works.

```json
{
  "pushToStartToken": "hex…",        // or null
  "login": "addisonk",
  "competitors": ["addisonk", "alice", "bob"],  // visible board, in board order (ties)
  "window": "daily",                 // "daily" | "weekly" | "monthly"
  "timeZone": "America/New_York",    // IANA
  "apnsEnvironment": "sandbox"       // "sandbox" | "production"
}
```

- Logins are lowercased, deduplicated, and kept in the order sent. If `login` is missing from
  `competitors`, it's put first, where the app places itself.
- At most 1,000 competitors, self included.
- Returns `201` on creation, `200` on update.
- A changed competitor list resets today's movement baseline, as a visibility change does in
  `RefreshCoordinator`.

### `PUT /v1/installations/{id}/activity`

`{"activityId": "…", "pushToken": "hex…"}`. Reports a new Live Activity, including ones the
relay started by push-to-start. The activity's age counts from this report. The next cron run
pushes the current state to it.

### `DELETE /v1/installations/{id}`

Sends an `end` event with immediate dismissal to the current activity, if any, and deletes the
registration. Returns `204`.

### Limits

- **Writes:** 30 per installation per 10 minutes; past that, `429`.
- **Bodies:** 128 KB at most.

## Board route

Lets another screen, such as the office TV's Glance, read one installation's board without the
installation secret (ticket #82).

### `GET /v1/installations/{id}/board?window=daily`

- **Auth:** `Authorization: Bearer <board read token>`, 32 to 256 characters. The installation
  secret is not accepted here, and a board read token can't call the device API.
- **Check order:** `window` first (400), then the token's presence and length (401), then the
  installation (404), and only then the token itself (401, 403). Looking up the installation before
  the token is deliberate: deleting an installation deletes its tokens, so a screen can still tell
  "Live rank is off" (404) from "this token was revoked" (403). It does reveal whether an
  installation ID exists to anyone sending a well-formed token; IDs are random UUIDs, so that
  isn't a way to find installations.
- **`window`:** `daily` (the default), `weekly` or `monthly`.
- **Reads only.** The board is computed from the cycle's `contribution_cache` and the installation's
  competitors, time zone, login and today's movement baseline by `deriveBoard` in `src/board.ts`,
  the same function the cycle pushes from. A read never fetches from GitHub and never writes, so
  read at the same moment it returns the state the cycle pushed.
- **Response** (`Cache-Control: private, max-age=60`, `Vary: Authorization`): the Live rank
  summary fields, plus the full visible board in board order.

  ```json
  {
    "window": "daily", "login": "me", "displayName": "Mae Example", "rank": 2, "competitorCount": 3, "contributions": 5,
    "above": { "login": "alice", "contributions": 9, "movementToday": 0 },
    "below": { "login": "bob", "contributions": 1, "movementToday": 0 },
    "movementToday": 0, "gapToPass": 4, "updatedAt": 1793804400,
    "rows": [
      { "rank": 1, "login": "alice", "contributions": 9, "movementToday": 0, "isSelf": false },
      { "rank": 2, "login": "me", "contributions": 5, "movementToday": 0, "isSelf": true },
      { "rank": 3, "login": "bob", "contributions": 1, "movementToday": 0, "isSelf": false }
    ]
  }
  ```

  - `rank`, `above`, `below` and `movementToday` follow the `LiveRankState` rules below: `rank`
    is null with no rivals or no data for you.
  - `gapToPass` is `max(above − yours, 1)`, null with nobody above (Swift `gapToPass`).
  - `displayName` is the `name` on your public GitHub profile, null when it's unknown or empty.
    The cron cycle looks it up (`GET https://api.github.com/users/<login>`, unauthenticated) at
    most once every 24 hours per installation, after its pushes, and keeps it in D1
    (`migrations/0003_display_name.sql`). A failed lookup keeps the last name and tries again the
    next day; a registration under another login forgets it. The board route only reads it.
  - A row's `contributions` is null when that login has no data yet.
  - `updatedAt` (Unix seconds) follows Live rank's rule: when your own count was fetched, else
    the time of the read (as the cycle uses its run time). A rival's older data never dates the
    board, so it's never null.
- **Errors** are `{ "error": "<code>", "message": "<text>" }` with `Cache-Control: no-store`:

  | Status | `error` | When |
  |---|---|---|
  | 401 | `unauthorized` | Token missing, malformed (under 32 or over 256 characters) or unknown |
  | 403 | `revoked` | The token was revoked |
  | 403 | `forbidden` | The token belongs to another installation |
  | 404 | `not_found` | The installation is gone (Live rank turned off, GitHub disconnected) |
  | 400 | `invalid_window` | `window` isn't `daily`, `weekly` or `monthly` |

### Board read tokens

The `board_tokens` table (`migrations/0002_board_tokens.sql`) stores each token's SHA-256 with
its installation ID, an optional label, and created and revoked times. Deleting the installation
deletes its tokens. For now tokens are minted by hand; a later iPhone setting can mint them
through a route.

**Mint** a token. Find the installation first; pick the production one that was updated most recently:

```bash
cd relay
npx wrangler d1 execute committed-relay --remote --command \
  "SELECT id, apns_environment, datetime(updated_at, 'unixepoch') AS updated FROM installations WHERE login = 'addisonk'"

INSTALLATION=<id from above>
TOKEN=$(openssl rand -hex 32)                                  # 64 characters; keep it, it's shown once
HASH=$(printf %s "$TOKEN" | shasum -a 256 | cut -d' ' -f1)     # printf, not echo: no trailing newline
npx wrangler d1 execute committed-relay --remote --command \
  "INSERT INTO board_tokens (token_hash, installation_id, label, created_at) VALUES ('$HASH', '$INSTALLATION', 'Office Frame', unixepoch())"

curl -H "Authorization: Bearer $TOKEN" \
  "https://committed-relay.prompt-hunt.workers.dev/v1/installations/$INSTALLATION/board?window=daily"
```

Keep the token out of the repository. Only its hash is in D1, so a lost token can't be recovered:
mint a new one.

**List** an installation's tokens, and **revoke** one by label, or by hash if you still have the token:

```bash
npx wrangler d1 execute committed-relay --remote --command \
  "SELECT label, datetime(created_at, 'unixepoch') AS created, datetime(revoked_at, 'unixepoch') AS revoked FROM board_tokens WHERE installation_id = '$INSTALLATION'"
npx wrangler d1 execute committed-relay --remote --command \
  "UPDATE board_tokens SET revoked_at = unixepoch() WHERE installation_id = '$INSTALLATION' AND label = 'Office Frame' AND revoked_at IS NULL"
npx wrangler d1 execute committed-relay --remote --command \
  "UPDATE board_tokens SET revoked_at = unixepoch() WHERE token_hash = '$HASH'"
```

A revoked token gets `403` from then on.

## Web widget

Committed's StandBy pair as a web page, so any screen can show your board: the iPhone app's hero
card (`BoardSummaryView`, rank only) beside the board list. Glance on the office Frame iframes it (ticket #83; ADR 0001 in `addisonk/glance`).

### `GET /v1/widget?layout=standby`

- **Public, static, no data.** `widget/standby.html`, `standby.css`, `standby.js`, the Inter
  Tight Regular and ExtraBold fonts and JetBrains Mono Medium (the eyebrows' monospace; the TV has
  none), subset to Basic Latin, `·`, `–` and `…` (about 10 KB), are bundled into the Worker (the `rules` in
  `wrangler.jsonc`) and served by `src/widget.ts` under `/v1/widget/`. `layout` defaults to
  `standby`, the only layout; any other is a `404`. The page may be framed from any origin.
- **Address:** `https://committed-relay.prompt-hunt.workers.dev/v1/widget?layout=standby#installation=<id>&token=<board read token>`.
  The installation ID and token are in the **fragment**, which browsers never send to a server.
  The page calls `GET /v1/installations/{id}/board?window=daily` on the same origin (no CORS)
  with `Authorization: Bearer <token>`; the token never appears in a request URL. Add
  `&window=weekly` or `&window=monthly` to the fragment for another Window.
- **Refresh:** every 5 minutes, in step with the cycle (every minute until the first board
  arrives). A failed refresh keeps the last board.
- **States:**

  | When | Shows |
  |---|---|
  | Before the first board | A `–` placeholder and "Your board is loading", never 0 |
  | Data more than 20 minutes old (`updatedAt`) | Live rank's stale treatment: colors step down (lime to deep lime, rank to grey, the field dims); the age stays soft |
  | No rivals | The trophy in place of a rank, your count, "Just you so far" |
  | No count of yours yet | The trophy, "Waiting for your first count" |
  | `401` / `403` | "This screen's access was revoked" |
  | `404` | "Live rank is off on your iPhone" |
  | No fragment | How to add the installation ID and token |

- **The card:** a folio ("01 · TODAY", "02 · 7 DAYS", "03 · 30 DAYS" … "YOUR RANK") over a
  hairline; your avatar with a lime ring, your first name (`displayName`'s first word, as the app
  shows it) over `@login`, or `@login` alone; your rank huge with "of N"; then today's movement
  ("Up 2 today" in lime, "Down 1 today" in soft, nothing when you held), the pass line ("5 to pass
  mossbyte", none at #1) and "Updated 6 min ago" (the app's coarse age). Your count stays on your
  row. Behind the rank sits the app's square field, drawn still for the card's size with its
  masks folded into each square's opacity. The list's header is the eyebrow "12 PEOPLE · TODAY".
- **Layout:** one rem scales with the box, so the pair fills whatever size it's given (a box
  taller than wide stacks the card over the list). The rank shrinks to fit the card; in a box too
  small for it the card drops your identity first, then the age, the movement line and the
  folio's label. The list shows as many rows as fit, chosen
  as the small Board widget chooses them (`WidgetSnapshot.boardRows`): the leaders, or the first
  few, the person ahead of you and you. Long logins lose their middle. Avatars load from GitHub
  over initials.
- **Motion:** row counts tick up, rows slide to their new places (FLIP with transforms), and
  movement chevrons fade in.

### Runtime limits (Samsung Frame, Chromium 76)

ES5 JavaScript only. No CSS flex `gap`, `inset`, `aspect-ratio`, `clamp()`, `min()`, `max()` or
custom properties; no gradients, shadows or blur; only `opacity` and `transform` animate. Fonts
and icons come from the relay; only avatars come from GitHub. `test/widget-runtime.test.ts`
checks all of this in `npm test` against the exact files the route serves (ES5 via `acorn`).

### Browser tests

`browser/widget.spec.ts` drives the page in Playwright against a stubbed board route: every
state above, the poll, the stale switch, the token staying out of URLs, the row swap and count
tick, and no overflow at 1280×1080, 852×393, 360×240 and 400×900.

```bash
npx playwright install chromium   # once
npm run test:browser
WIDGET_SCREENS=/some/dir npm run test:browser   # also save a screenshot of each state
```

## What the cron run does

`src/cycle.ts`, once every 5 minutes:

1. **Counts.** Fetch `https://github.com/users/<login>/contributions` anonymously for every
   login across all installations, at most once per login per 5 minutes; D1's
   `contribution_cache` is shared by everyone. Parse with `src/parser.ts`, a port of
   `ContributionsParser.swift` tested with the same cases. If a fetch fails, the last good days
   are kept with their real age, so a hiccup doesn't zero anyone. A login never fetched has no
   data and shows as a placeholder.
2. **Windows.** Today, 7 days, and 30 days are summed against the installation's local
   calendar date in its IANA time zone, not UTC.
3. **Ranking.** `src/ranking.ts` ports `Ranking.order`. `src/liveRank.ts` derives
   `LiveRankState`, matching `LiveRankAttributes.ContentState`. `updatedAt` is when your own
   count was fetched, or the run time when you have no data.
4. **Today's movement.** This mirrors `RefreshCoordinator.updateDailyRankDeltas`. The first run
   of each local day captures the daily ranks of rows that have data. Later runs report
   `baseline − current` for you, on the Today window only.
5. **Pushes.**
   - It pushes `update` only when the state (ignoring `updatedAt`) changed.
   - It also sends a heartbeat when the last push is within 5 minutes of its stale date and
     newer data exists.
   - Priority is `10` only when your rank changed, otherwise `5`.
   - Headers are `apns-push-type: liveactivity` and `apns-topic: <APNS_BUNDLE_ID>.push-type.liveactivity`.
   - Every push carries `stale-date = updatedAt + 20 min`.
6. **Rotation.**
   - At 7.5 hours of activity age, it sends `end` with `dismissal-date = now`, then push-to-start
     (`event: start`, `attributes-type: LiveRankAttributes`, `attributes: {selfLogin}`, with an
     alert and no sound).
   - With a push-to-start token but no activity, it restarts only 7.5 hours after the last
     start, or after registration if nothing has started yet.
   - Today resets in place at local midnight; that's just a state change.
7. **Dead tokens.** `410`, or `400` with `BadDeviceToken` or `DeviceTokenNotForTopic`, clears
   the token that was used.

APNs auth is an ES256 JWT signed with WebCrypto from the `.p8` key and cached for 50 minutes.

## Conformance fixture

`../fixtures/ranking-conformance.json` is shared with the Mac test target, so the Swift
ordering and this port can't drift.

```json
{
  "version": 1,
  "cases": [{
    "name": "…",
    "input": {
      "self": "me",
      "competitors": ["me", "alice", "bob"],            // board order, self included
      "window": "daily",
      "standings": { "me": { "contributions": 50, "window": "daily" } },  // absent = no data
      "rankDeltas": { "me": 1, "alice": -1 },            // today's baseline − current
      "now": 1793800000                                  // Unix seconds of the data
    },
    "expected": {
      "order": [{ "login": "alice", "rank": 1 }],
      "liveRankState": { "window": "daily", "rank": 2, "competitorCount": 3, "contributions": 50,
                         "above": { "login": "alice", "contributions": 90, "movementToday": -1 },
                         "below": { "login": "bob", "contributions": 20, "movementToday": 0 },
                         "movementToday": 1, "updatedAt": 1793800000 }
    }
  }]
}
```

- `test/ranking.test.ts` checks `order` and `liveRankState`.
- `CommitStandingsTests/RankingConformanceTests.swift` checks `order` against `Ranking.order`.
  It finds the file through `#filePath`, so the fixture isn't a bundle resource. The Swift
  `LiveRankState` derivation (#43) should extend that test to check `liveRankState` too.
- A standing whose `window` differs from the case's `window` counts as missing.
- `LiveRankState` rules:
  - `rank` is null with no data for you, or with no visible rivals.
  - `above` and `below` are null when there's no rank, or when that neighbor has no data.
  - `movementToday`, yours and each neighbor's in `above`/`below`, is that login's
    `rankDeltas` entry on `daily`, and 0 outside it. The app decodes a neighbor without it as 0.
- Add a case for any ranking behavior change, and run both suites.

## Setup (provisioning ticket)

1. Run the HTTP/2 spike above.
2. Create the database and paste its id into `wrangler.jsonc` → `d1_databases[0].database_id`:
   ```bash
   cd relay && npm ci
   npx wrangler d1 create committed-relay
   npx wrangler d1 migrations apply committed-relay --remote
   ```
3. Set the APNs secrets. The key needs the APNs service enabled in the Apple Developer account:
   ```bash
   npx wrangler secret put APNS_KEY_ID        # 10-character key ID
   npx wrangler secret put APNS_TEAM_ID       # 10-character team ID
   npx wrangler secret put APNS_PRIVATE_KEY < AuthKey_XXXXXXXXXX.p8
   ```
   `APNS_BUNDLE_ID` is a var in `wrangler.jsonc` (`com.addisonk.CommitStandings.iOS`).
4. Deploy with `npx wrangler deploy`. The cron trigger deploys with it.
5. Plan limits: each run makes one subrequest per uncached login, plus one per push. The
   Workers Free plan's per-invocation subrequest cap (50 at the time of writing) only covers a
   small board, so use Workers Paid for real use. Check current limits before deploying.

## Local development

```bash
cd relay
npm ci
npm run typecheck
npm test                                    # Vitest in workerd: fake APNs, fake GitHub, local D1
npm run test:browser                        # Playwright: the web widget against a stubbed board
npx wrangler d1 migrations apply committed-relay --local
npx wrangler dev --test-scheduled           # then: curl "localhost:8787/__scheduled?cron=*/5+*+*+*+*"
```

Local runs fetch real GitHub pages. Pushes to Apple fail locally (see the spike), and are logged
without tokens.

### With the iPhone app and a fake APNs

To watch the whole loop locally, point the relay at `dev/fake-apns.mjs`, which prints each push
and answers 200. Put this in `relay/.dev.vars` (gitignored), with a throwaway P-256 key so the
provider token can be signed:

```bash
node -e "const {generateKeyPairSync}=require('crypto');const k=generateKeyPairSync('ec',{namedCurve:'P-256'}).privateKey.export({type:'pkcs8',format:'pem'});console.log('APNS_KEY_ID=\"LOCALKEY01\"\nAPNS_TEAM_ID=\"LOCALTEAM1\"\nAPNS_PRIVATE_KEY=\"'+k.trim().replace(/\n/g,'\\\\n')+'\"\nAPNS_ORIGIN=\"http://127.0.0.1:8788\"')" > .dev.vars
node dev/fake-apns.mjs &                    # fake APNs on 127.0.0.1:8788
npx wrangler dev --test-scheduled --ip 127.0.0.1 --port 8787
```

Build the iPhone app with `COMMITTED_RELAY_URL=http://localhost:8787` (Debug) and run it in the
simulator. The Debug screenshot fixture works offline: launch with
`-ScreenshotFixture -RelayDisclosureAccepted` and the app registers its fixture board, its
push-to-start token, and its activity's push token. The simulator issues both tokens once the app
has `aps-environment`. To change a count without GitHub, seed the shared cache (it's fresh for 5
minutes, so the cycle won't refetch). Use today's date in the registration's time zone:

```bash
npx wrangler d1 execute committed-relay --local --command \
  "INSERT OR REPLACE INTO contribution_cache VALUES ('ari-linden', strftime('%s','now'), strftime('%s','now'), '{\"2026-11-04\": 10}', NULL)"
curl "localhost:8787/__scheduled?cron=*/5+*+*+*+*"
```

The fake APNs prints the `update` (or the `end` and push-to-start `start` at rotation) with its
content state. Apple's simulator can't receive a Live Activity push from the relay (`simctl push`
delivers only ordinary notifications), so showing it in the Dynamic Island needs a device and
real APNs credentials.
