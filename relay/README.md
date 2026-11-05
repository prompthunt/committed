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
| Deployed Worker on Cloudflare's edge | **Not run.** The Cloudflare account available during the spike had no workers.dev subdomain. `wrangler deploy` and `wrangler dev --remote` both stop with error 10063 ("You need a workers.dev subdomain"). Cron-only deploys stop there too. Registering a subdomain changes the account, so the spike left it for the provisioning ticket. The throwaway script that was uploaded has been deleted. |

**What this means:**

- **Local `wrangler dev` cannot reach APNs.** Local workerd's outbound `fetch` is HTTP/1.1.
  Tests and local runs use a fake APNs (`test/support/fakes.ts`); everything else (device
  API, D1, cron via `--test-scheduled`, real GitHub fetches) works locally.
- **The edge is still unconfirmed.** There's indirect evidence that it works: maintained
  Workers-native APNs clients such as
  [`@fivesheepco/cloudflare-apns2`](https://www.npmjs.com/package/@fivesheepco/cloudflare-apns2)
  send with plain `fetch` and no Node compatibility layer.

**Chosen runtime: Cloudflare Workers, as the spec says, pending the edge check.** All APNs I/O
sits behind the small `ApnsSender` interface (`src/apns.ts`). If the edge check fails, only that
transport moves, not the relay logic.

**First step of the provisioning ticket** (about a minute, needs a workers.dev subdomain):

```bash
cd relay
npx wrangler deploy -c spike/wrangler.spike.jsonc
curl https://committed-apns-spike.<your-subdomain>.workers.dev/   # {"http2": true, ...} means Workers works
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
      "rankDeltas": { "me": 1 },                         // today's baseline − current
      "now": 1793800000                                  // Unix seconds of the data
    },
    "expected": {
      "order": [{ "login": "alice", "rank": 1 }],
      "liveRankState": { "window": "daily", "rank": 2, "competitorCount": 3, "contributions": 50,
                         "above": { "login": "alice", "contributions": 90 },
                         "below": { "login": "bob", "contributions": 20 },
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
  - `movementToday` is 0 outside `daily`.
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
  "INSERT OR REPLACE INTO contribution_cache VALUES ('sam-rivera', strftime('%s','now'), strftime('%s','now'), '{\"2026-11-04\": 10}', NULL)"
curl "localhost:8787/__scheduled?cron=*/5+*+*+*+*"
```

The fake APNs prints the `update` (or the `end` and push-to-start `start` at rotation) with its
content state. Apple's simulator can't receive a Live Activity push from the relay (`simctl push`
delivers only ordinary notifications), so showing it in the Dynamic Island needs a device and
real APNs credentials.
