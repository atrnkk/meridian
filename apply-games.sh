#!/bin/sh
# Applies every games/*/views.sql to ClickHouse as the admin user.
# Safe to re-run as long as the files use IF NOT EXISTS.
set -eu
cd "$(dirname "$0")"

for file in games/*/views.sql; do
    echo "Applying $file"
    docker compose exec -T clickhouse clickhouse-client --multiquery < "$file"
done
