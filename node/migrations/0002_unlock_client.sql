-- Unlock attempts per client (T1-NODE-VIEW-GATE amendment 2): the request's CF-Connecting-IP, or a
-- fixed fallback key when the header is absent. Rows written before this migration have NULL.
ALTER TABLE unlock_attempt ADD COLUMN client_key TEXT;
CREATE INDEX unlock_attempt_failures ON unlock_attempt (succeeded, client_key, attempted_at);
