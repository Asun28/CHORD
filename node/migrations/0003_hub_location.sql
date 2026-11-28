-- Fictional hub coordinates (T1-NODE-HALL-PRINT owner decision), so posture matches feed areas to hubs.
-- The seed writes them for a fresh D1; the updates give a D1 seeded before this migration the same values.
ALTER TABLE hub ADD COLUMN lat REAL;
ALTER TABLE hub ADD COLUMN lon REAL;
UPDATE hub SET lat = -41.28, lon = 174.78 WHERE id = 'hub-ferncliff' AND fictional = 1;
UPDATE hub SET lat = -41.15, lon = 174.92 WHERE id = 'hub-larkhollow' AND fictional = 1;
UPDATE hub SET lat = -41.31, lon = 174.81 WHERE id = 'hub-quillwick' AND fictional = 1;
