-- Drasi/Debezium replication setup for Azure Database for PostgreSQL Flexible Server.
-- Flexible Server forbids SUPERUSER, so this replaces data/drasi-setup.sql's superuser
-- role with the two Azure/Debezium-sanctioned mechanisms:
--   * REPLICATION via azure_pg_admin membership
--       (learn.microsoft.com/azure/postgresql/flexible-server/concepts-logical)
--   * a replication group to share ownership of the already-existing tables, so
--     Debezium (publication.autocreate.mode=filtered) can add them to its publication
--       (drasi.io .../configure-postgresql-source setup guide)
-- wal_level=logical + max_worker_processes are set on the server by the recipe.
-- Run as the admin (stepupadmin). Drasi password: psql -v drasi_password=... (never hardcoded).

-- 1. Replication role (idempotent; no SUPERUSER).
SELECT 'CREATE ROLE drasi LOGIN PASSWORD ' || quote_literal(:'drasi_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'drasi')
\gexec

GRANT azure_pg_admin TO drasi;   -- Flexible Server: enables REPLICATION + CREATE PUBLICATION
ALTER ROLE drasi WITH LOGIN REPLICATION PASSWORD :'drasi_password';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO drasi;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO drasi;

-- 2. Replication group: share ownership of the existing tables so Debezium (as drasi)
--    can add them to its filtered publication. The admin stays a member, so the app
--    (which connects as stepupadmin) keeps full read/write access via inheritance.
SELECT 'CREATE ROLE replication_group'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replication_group')
\gexec

GRANT replication_group TO stepupadmin;   -- original table owner (= recipe administratorLogin)
GRANT replication_group TO drasi;         -- Debezium replication user

ALTER TABLE participants    OWNER TO replication_group;
ALTER TABLE step_logs       OWNER TO replication_group;
ALTER TABLE daily_targets   OWNER TO replication_group;
ALTER TABLE challenge_state OWNER TO replication_group;