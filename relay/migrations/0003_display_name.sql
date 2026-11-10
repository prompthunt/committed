-- The installation owner's public GitHub name, for the board route's `displayName` (the web
-- widget's hero card). The cron cycle looks it up at most once a day per installation from
-- api.github.com/users/<login>, unauthenticated; a failed lookup keeps the last name and waits a
-- day. Board reads never call GitHub.

ALTER TABLE installations ADD COLUMN display_name TEXT;              -- public profile name; NULL when unknown or empty
ALTER TABLE installations ADD COLUMN display_name_checked_at INTEGER; -- Unix seconds of the last lookup attempt
