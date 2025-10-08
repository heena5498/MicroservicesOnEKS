-- name: GetPlatformOverview :one
SELECT
    COUNT(*) FILTER (WHERE status = 'published') as total_published_events,
    COUNT(*) FILTER (WHERE status = 'draft') as total_draft_events,
    SUM(total_capacity - available_seats) FILTER (WHERE status = 'published') as total_tickets_sold,
    SUM(total_capacity) FILTER (WHERE status = 'published') as total_capacity,
    ROUND(
        COALESCE(
            SUM(total_capacity - available_seats) FILTER (WHERE status = 'published')::decimal /
            NULLIF(SUM(total_capacity) FILTER (WHERE status = 'published'), 0) * 100,
            0
        ),
        2
    ) as overall_utilization
FROM events;

-- name: GetTopEventsByTicketsSold :many
SELECT
    event_id,
    name,
    total_capacity,
    available_seats,
    (total_capacity - available_seats) as tickets_sold,
    ROUND(((total_capacity - available_seats)::decimal / total_capacity::decimal) * 100, 2) as utilization,
    base_price,
    ROUND((total_capacity - available_seats) * base_price::decimal, 2) as revenue
FROM events
WHERE status = 'published'
ORDER BY tickets_sold DESC
LIMIT $1;
