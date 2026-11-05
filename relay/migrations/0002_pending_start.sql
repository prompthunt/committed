-- When the relay last sent a push-to-start that no reported activity has claimed yet (Unix
-- seconds). A relay-started activity is that old when the app reports it, not brand new.
ALTER TABLE installations ADD COLUMN pending_start_at INTEGER;
