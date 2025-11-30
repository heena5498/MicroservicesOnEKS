-- +goose Up
-- Migrate waitlist to timestamp-based ordering instead of position integers

-- Drop position constraint and index
ALTER TABLE waitlist DROP CONSTRAINT IF EXISTS check_position;
DROP INDEX IF EXISTS idx_waitlist_event_position;

-- Make position nullable (we'll calculate it on-demand)
ALTER TABLE waitlist ALTER COLUMN position DROP NOT NULL;

-- Add index on joined_at for ordering (critical for performance)
CREATE INDEX idx_waitlist_event_joined ON waitlist(event_id, joined_at) WHERE status = 'waiting';

-- Add index for position calculation queries
CREATE INDEX idx_waitlist_event_status_joined ON waitlist(event_id, status, joined_at);

-- +goose Down
-- Revert to position-based system
DROP INDEX IF EXISTS idx_waitlist_event_joined;
DROP INDEX IF EXISTS idx_waitlist_event_status_joined;

ALTER TABLE waitlist ALTER COLUMN position SET NOT NULL;

CREATE INDEX idx_waitlist_event_position ON waitlist(event_id, position) WHERE status = 'waiting';

ALTER TABLE waitlist ADD CONSTRAINT check_position CHECK (position > 0);
