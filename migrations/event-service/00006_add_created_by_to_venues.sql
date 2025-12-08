-- +goose Up
-- +goose StatementBegin
ALTER TABLE venues
ADD COLUMN created_by UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000';

-- Remove default after adding the column
ALTER TABLE venues
ALTER COLUMN created_by DROP DEFAULT;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE venues
DROP COLUMN created_by;
-- +goose StatementEnd
