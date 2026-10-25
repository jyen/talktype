-- talktype feedback-loop store (D1)

-- Corrections you add over time. Two kinds:
--   'vocab'   -> a correct spelling to feed whisper's hint + the cleanup "fix these" rule.
--               right = the correct term; wrong may be NULL (or the common mis-hearing).
--   'replace' -> deterministic post-cleanup text swap, wrong -> right (whole-word, case-insensitive).
-- scope: optional app-name substring (e.g. "mail") to limit a correction to certain apps; NULL = all.
CREATE TABLE IF NOT EXISTS corrections (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  kind       TEXT NOT NULL DEFAULT 'vocab',   -- 'vocab' | 'replace'
  wrong      TEXT,
  "right"    TEXT NOT NULL,
  scope      TEXT,
  active     INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_corrections_active ON corrections(active);

-- Optional history log (what whisper heard vs what we returned), for reviewing misfires.
-- Gated by the LOG_DICTATIONS var; drop/ignore if you don't want transcripts stored.
CREATE TABLE IF NOT EXISTS dictations (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  app        TEXT,
  raw        TEXT,
  cleaned    TEXT,
  bytes      INTEGER,
  stt_ms     INTEGER,
  clean_ms   INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_dictations_created ON dictations(created_at);
