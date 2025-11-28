-- +goose Up
ALTER TABLE waitlist DROP COLUMN position;

-- +goose Down
ALTER TABLE waitlist ADD COLUMN position INTEGER;
CREATE INDEX idx_waitlist_event_position ON waitlist(event_id, position) WHERE status = 'waiting';
ALTER TABLE waitlist ADD CONSTRAINT check_position CHECK (position > 0);
