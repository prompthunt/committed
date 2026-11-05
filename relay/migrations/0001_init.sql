-- Committed relay schema. One row per registered iPhone installation, plus a shared
-- per-login cache of public contribution days. No GitHub token is ever stored.

CREATE TABLE installations (
  id TEXT PRIMARY KEY,                 -- random install ID chosen by the device
  secret_hash TEXT NOT NULL,           -- hex SHA-256 of the bearer install secret
  apns_environment TEXT NOT NULL,      -- 'sandbox' | 'production'
  push_to_start_token TEXT,            -- Activity<LiveRankAttributes>.pushToStartToken (hex)
  activity_id TEXT,                    -- current Live Activity id
  activity_push_token TEXT,            -- that activity's update token (hex)
  activity_started_at INTEGER,         -- Unix seconds the activity started (device report or relay start)
  last_start_at INTEGER,               -- Unix seconds of the relay's last push-to-start
  login TEXT NOT NULL,                 -- the user's own GitHub login (public)
  competitors_json TEXT NOT NULL,      -- JSON array of visible competitor logins, in board order
  window TEXT NOT NULL,                -- 'daily' | 'weekly' | 'monthly'
  time_zone TEXT NOT NULL,             -- IANA time zone, e.g. 'America/New_York'
  baseline_date TEXT,                  -- local YYYY-MM-DD the movement baseline was captured
  baseline_ranks_json TEXT,            -- JSON {login: rank} at the day's first run
  last_state_json TEXT,                -- last LiveRankState pushed
  last_push_at INTEGER,                -- Unix seconds of the last successful push
  rate_window_start INTEGER NOT NULL DEFAULT 0, -- start of the current write rate-limit window
  rate_count INTEGER NOT NULL DEFAULT 0,        -- writes in the current window
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE contribution_cache (
  login TEXT PRIMARY KEY,
  attempted_at INTEGER NOT NULL,       -- Unix seconds of the last fetch attempt (cache key, 5 minutes)
  fetched_at INTEGER,                  -- Unix seconds of the last successful fetch
  days_json TEXT,                      -- JSON {"YYYY-MM-DD": count} from the last successful fetch
  error TEXT                           -- last failure reason, for logs only
);
