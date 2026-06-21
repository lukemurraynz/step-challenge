#!/usr/bin/env bash
set -euo pipefail

# --- config ---
CONTAINER=stepup-pg
PG_IMAGE=docker.io/library/postgres:16
PG_PASSWORD=postgres
PG_DB=stepup
VOLUME=stepup-pgdata
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$ROOT/data"

# --- optional clean slate: ./db-up.sh --fresh ---
if [[ "${1:-}" == "--fresh" ]]; then
  echo "Tearing down for a fresh start..."
  podman rm -f "$CONTAINER" 2>/dev/null || true
  podman volume rm "$VOLUME" 2>/dev/null || true
fi

# --- 1. ensure the podman machine is running (Windows/macOS) ---
if ! podman info >/dev/null 2>&1; then
  echo "Starting podman machine..."
  podman machine start
fi

# --- 2. start (or create) Postgres with logical replication ---
if podman container exists "$CONTAINER"; then
  echo "Container '$CONTAINER' exists; (re)starting it..."
  podman start "$CONTAINER" >/dev/null
else
  echo "Creating container '$CONTAINER'..."
  podman run -d --name "$CONTAINER" \
    -e POSTGRES_PASSWORD="$PG_PASSWORD" \
    -p 5432:5432 \
    -v "$VOLUME:/var/lib/postgresql/data" \
    "$PG_IMAGE" \
    -c wal_level=logical \
    -c max_replication_slots=10 \
    -c max_wal_senders=10 >/dev/null
fi

# --- 3. wait until Postgres accepts connections ---
echo -n "Waiting for Postgres"
until podman exec "$CONTAINER" pg_isready -U postgres -q; do
  echo -n "."
  sleep 1
done
echo " ready."

# --- 4. create the database if it doesn't exist ---
if podman exec "$CONTAINER" psql -U postgres -tAc \
     "SELECT 1 FROM pg_database WHERE datname='$PG_DB'" | grep -q 1; then
  echo "Database '$PG_DB' already exists."
else
  echo "Creating database '$PG_DB'..."
  podman exec "$CONTAINER" psql -U postgres -c "CREATE DATABASE $PG_DB"
fi

# --- 5. apply schema + seed via stdin (no container paths to mangle) ---
echo "Applying schema..."
podman exec -i "$CONTAINER" psql -U postgres -d "$PG_DB" -v ON_ERROR_STOP=1 < "$DATA_DIR/schema.sql"

echo "Seeding participants..."
podman exec -i "$CONTAINER" psql -U postgres -d "$PG_DB" -v ON_ERROR_STOP=1 < "$DATA_DIR/seed.sql"

echo "Postgres up on localhost:5432 — database '$PG_DB' ready."