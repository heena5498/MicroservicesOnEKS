
-- name: JoinWaitlist :one
INSERT INTO waitlist (
    event_id, user_id, quantity_requested
) VALUES (
    $1, $2, $3
) RETURNING waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at;

-- name: GetWaitlistEntry :one
SELECT waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at
FROM waitlist WHERE waitlist_id = $1;

-- name: GetUserWaitlistEntry :one
SELECT waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at
FROM waitlist WHERE user_id = $1 AND event_id = $2;

-- name: GetWaitlistPosition :one
WITH numbered AS (
    SELECT
        waitlist_id,
        user_id,
        status,
        ROW_NUMBER() OVER (ORDER BY joined_at ASC) as position
    FROM waitlist
    WHERE event_id = $2 AND status = 'waiting'
)
SELECT position, status FROM numbered
WHERE user_id = $1;

-- name: GetEventWaitlist :many
SELECT waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at
FROM waitlist
WHERE event_id = $1 AND status = 'waiting'
ORDER BY joined_at ASC
LIMIT $2;

-- name: GetNextWaitlistEntries :many
SELECT waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at
FROM waitlist
WHERE event_id = $1 AND status = 'waiting'
ORDER BY joined_at ASC
LIMIT $2;

-- name: UpdateWaitlistStatus :one
UPDATE waitlist
SET status = COALESCE($2, status),
    updated_at = CURRENT_TIMESTAMP,
    offered_at = CASE WHEN $2::text = 'offered' THEN CURRENT_TIMESTAMP ELSE offered_at END,
    converted_at = CASE WHEN $2::text = 'converted' THEN CURRENT_TIMESTAMP ELSE converted_at END,
    expires_at = $3
WHERE waitlist_id = $1
RETURNING waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at;

-- name: SetWaitlistOffered :one
UPDATE waitlist
SET status = 'offered',
    offered_at = CURRENT_TIMESTAMP,
    expires_at = $2,
    updated_at = CURRENT_TIMESTAMP
WHERE waitlist_id = $1
RETURNING waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at;

-- name: SetWaitlistWaiting :one
UPDATE waitlist
SET status = 'waiting',
    expires_at = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE waitlist_id = $1
RETURNING waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at;

-- name: GetOfferedWaitlistEntries :many
SELECT waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at
FROM waitlist
WHERE status = 'offered' AND expires_at < CURRENT_TIMESTAMP;

-- name: RemoveFromWaitlist :exec
DELETE FROM waitlist WHERE user_id = $1 AND event_id = $2;

-- name: GetWaitlistStats :one
SELECT
    COUNT(*) as total_waiting,
    COALESCE(AVG(quantity_requested), 0.0) as avg_quantity_requested
FROM waitlist
WHERE event_id = $1 AND status = 'waiting';

-- name: GetExpiredWaitlistOffers :many
SELECT waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at
FROM waitlist
WHERE status = 'offered'
    AND expires_at IS NOT NULL
    AND expires_at < CURRENT_TIMESTAMP;

-- name: GetWaitlistEntryByUserAndEvent :one
SELECT waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at
FROM waitlist
WHERE user_id = $1 AND event_id = $2;

-- name: GetWaitlistEntryWithPosition :one
WITH numbered AS (
    SELECT
        waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at,
        ROW_NUMBER() OVER (ORDER BY joined_at ASC) as calculated_position
    FROM waitlist
    WHERE event_id = $2 AND status = 'waiting'
)
SELECT waitlist_id, event_id, user_id, quantity_requested, status, joined_at, offered_at, expires_at, converted_at, created_at, updated_at, calculated_position
FROM numbered
WHERE user_id = $1;
