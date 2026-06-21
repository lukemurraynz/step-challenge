#!/usr/bin/env bash
set -euo pipefail
podman rm -f stepup-pg 2>/dev/null || true
echo "Stopped stepup-pg (volume kept; add 'podman volume rm stepup-pgdata' to wipe data)."