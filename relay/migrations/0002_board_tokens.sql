-- Board read tokens (ticket #82): revocable, read-only credentials that let another screen
-- (the office TV) read one installation's board without the installation secret. Only the
-- token's SHA-256 is stored. Deleting the installation deletes its tokens.

CREATE TABLE board_tokens (
  token_hash TEXT PRIMARY KEY,         -- hex SHA-256 of the bearer board token
  installation_id TEXT NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
  label TEXT,                          -- where the token lives, e.g. 'Office Frame'
  created_at INTEGER NOT NULL,         -- Unix seconds
  revoked_at INTEGER                   -- Unix seconds; NULL while the token is valid
);

CREATE INDEX board_tokens_installation ON board_tokens(installation_id);
