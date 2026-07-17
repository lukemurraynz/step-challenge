-- Drasi/Debezium replication for Azure Database for PostgreSQL Flexible Server.
-- Flexible Server won't let the admin transfer table ownership or grant on the
-- `public` schema (it isn't the schema owner), so a separate least-priv role can't
-- be made a table owner. Use Azure's documented pattern: make the ADMIN the
-- replication user — stepupadmin already owns the tables (schema.sql created them)
-- and is azure_pg_admin, so Debezium creates its publication + slot with no transfer.
--   learn.microsoft.com/azure/postgresql/flexible-server/concepts-logical
-- wal_level=logical + max_worker_processes are set on the server by the recipe.
ALTER ROLE stepupadmin WITH REPLICATION;