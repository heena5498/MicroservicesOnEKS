-- +goose Up
-- +goose StatementBegin
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE events
ADD CONSTRAINT no_overlapping_events
EXCLUDE USING GIST (
    venue_id WITH =,
    tsrange(start_datetime, end_datetime) WITH &&
)
WHERE (status != 'cancelled');
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE events DROP CONSTRAINT IF EXISTS no_overlapping_events;
-- +goose StatementEnd
