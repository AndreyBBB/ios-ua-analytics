-- ─────────────────────────────────────────────────────────────────────────────
-- Runs automatically on first ClickHouse startup.
-- Creates all four schemas (databases in ClickHouse terminology).
-- dbt will create the actual tables inside these schemas.
-- ─────────────────────────────────────────────────────────────────────────────

-- Layer 0: Raw landing zone — immutable, never modified after load
CREATE DATABASE IF NOT EXISTS raw;

-- Layer 1: Staging — cleaned, typed, renamed (managed by dbt)
CREATE DATABASE IF NOT EXISTS staging;

-- Layer 2: Intermediate — business logic, joins, enrichment (managed by dbt)
CREATE DATABASE IF NOT EXISTS intermediate;

-- Layer 3: Marts — final analytics tables, BI connects here (managed by dbt)
CREATE DATABASE IF NOT EXISTS marts;
