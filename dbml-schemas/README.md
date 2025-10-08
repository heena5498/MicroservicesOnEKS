# Database Schema Visualization

This directory contains DBML (Database Markup Language) files for all three databases in the BookMyEvent platform.

## 📁 Files

-  **`users_db.dbml`** - User authentication and profile management
-  **`events_db.dbml`** - Event catalog, venues, and admin management
-  **`bookings_db.dbml`** - Booking transactions, payments, and waitlist

## 🔗 Key Relationships

### Cross-Database References (Application-Level)

Since we use a microservices architecture with separate databases:

-  **bookings.user_id** → users_db.users.user_id
-  **bookings.event_id** → events_db.events.event_id
-  **waitlist.user_id** → users_db.users.user_id
-  **waitlist.event_id** → events_db.events.event_id
-  **payments.user_id** → users_db.users.user_id
-  **payments.event_id** → events_db.events.event_id

These are enforced at the application level in the microservices, not as database foreign keys.

## 🎯 Important Notes

-  **Optimistic Locking**: The `events.version` column implements optimistic locking to prevent overselling
-  **Venue Overlap Prevention**: GIST exclusion constraint `no_overlapping_events` prevents double-booking venues by ensuring no time range overlap for non-cancelled events (atomic database-level guarantee)
-  **Two-Phase Booking**: Bookings have a 5-minute reservation window (tracked in `bookings.expires_at`)
-  **Waitlist Queue**: Uses Redis sorted sets in production, PostgreSQL table for persistence
-  **Idempotency**: `bookings.idempotency_key` prevents duplicate bookings from retries

## 🛠️ Updating Schemas

If you modify the database schemas in `migrations/` or `sqlc/`, remember to update these DBML files to keep the visualizations in sync.

## 📊 Alternative Tools

You can also use these DBML files with:

-  [dbdocs.io](https://dbdocs.io) - Generate hosted documentation
-  VS Code DBML extension - View in your editor
-  CI/CD pipelines - Auto-generate documentation on schema changes
