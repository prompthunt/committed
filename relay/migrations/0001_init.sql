-- One row per registered iPhone. Never holds a GitHub token: only public logins.
CREATE TABLE installations (
  id TEXT PRIMARY KEY,                      -- random install ID chosen by the device
  secret_hash TEXT NOT NULL,                -- hex SHA-256 of the bearer install secret
  environment TEXT NOT NULL,                -- 'sandbox' | 'production' (APNs host)
  push_to_start_token TEXT,                 -- hex; null when unknown or rejected by APNs
  login TEXT NOT NULL,                      -- your GitHub login (public)
  competitors TEXT NOT NULL,                -- JSON array of visible logins in roster order, self included
  window TEXT NOT NULL,                     -- 'daily' | 'weekly' | 'monthly'
  time_zone TEXT NOT NULL,                  -- IANA time zone for the local calendar day
  activity_id TEXT,                         -- current Live Activity, if any
  activity_push_token TEXT,                 -- hex update token of that activity
  activity_started_at INTEGER,              -- Unix seconds the activity started
  rotation_anchor_at INTEGER NOT NULL,      -- Unix seconds of the last start; restarts wait 7.5 h from here
  last_state TEXT,                          -- JSON LiveRankState last delivered to the activity
  last_stale_at INTEGER,                    -- stale date (Unix seconds) of that delivery
  baseline_day TEXT,                        -- local YYYY-MM-DD of the movement baseline
  baseline_ranks TEXT,                      -- JSON { login: rank } captured at the day's first run
  rate_window_start INTEGER NOT NULL DEFAULT 0,
  rate_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Public contribution graphs, shared across installations. Days are the page's calendar dates.
CREATE TABLE contribution_cache (
  login TEXT PRIMARY KEY,
  days TEXT NOT NULL,                       -- JSON { "YYYY-MM-DD": count } for the recent days
  fetched_at INTEGER NOT NULL               -- Unix seconds of the successful fetch
);

-- Small key/value store for relay-wide state (the cached APNs provider token).
CREATE TABLE relay_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
