-- CHORD web node schema (plan section 5). Timestamps are ISO 8601 UTC text.
CREATE TABLE source (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  cadence_seconds INTEGER NOT NULL
);

CREATE TABLE observation (
  id INTEGER PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES source(id),
  cap_identifier TEXT NOT NULL,
  msg_type TEXT NOT NULL CHECK (msg_type IN ('alert', 'update', 'cancel')),
  cap_json TEXT NOT NULL,
  sent_at TEXT NOT NULL,
  observed_at TEXT NOT NULL,
  fetched_at TEXT NOT NULL,
  expires_at TEXT,
  superseded_by INTEGER REFERENCES observation(id),
  superseded_at TEXT,
  UNIQUE (source_id, cap_identifier)
);
CREATE INDEX observation_active ON observation (observed_at, superseded_at, expires_at);

-- A Cancel or Update whose target has not arrived yet.
CREATE TABLE pending_reference (
  source_id TEXT NOT NULL,
  target_identifier TEXT NOT NULL,
  referencing_id INTEGER NOT NULL REFERENCES observation(id),
  sent_at TEXT NOT NULL,
  PRIMARY KEY (source_id, target_identifier, referencing_id)
);

CREATE TABLE hub (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  suburb TEXT NOT NULL,
  address TEXT NOT NULL,
  is_home INTEGER NOT NULL DEFAULT 0,
  fictional INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE hub_asset (
  id TEXT PRIMARY KEY,
  hub_id TEXT NOT NULL REFERENCES hub(id),
  kind TEXT NOT NULL,
  name TEXT NOT NULL,
  sensitivity TEXT NOT NULL CHECK (sensitivity IN ('public', 'restricted'))
);

CREATE TABLE role (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  priority_rank INTEGER NOT NULL,
  source_ref TEXT NOT NULL
);

CREATE TABLE task_template (
  id TEXT PRIMARY KEY,
  role_code TEXT NOT NULL REFERENCES role(code),
  phase TEXT NOT NULL,
  text TEXT NOT NULL,
  source_ref TEXT NOT NULL
);

CREATE TABLE feed_state (
  source_id TEXT PRIMARY KEY REFERENCES source(id),
  state TEXT NOT NULL CHECK (state IN ('running', 'paused')),
  changed_at TEXT NOT NULL
);

CREATE TABLE unlock_attempt (
  id INTEGER PRIMARY KEY,
  attempted_at TEXT NOT NULL,
  succeeded INTEGER NOT NULL
);
