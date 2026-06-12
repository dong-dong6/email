#!/usr/bin/env sh
set -eu

backup_dir="${1:?usage: scripts/restore.sh backups/YYYYmmdd-HHMMSS}"

docker compose exec -T postgres psql -U "${POSTGRES_USER:-email}" "${POSTGRES_DB:-email}" < "$backup_dir/postgres.sql"
docker run --rm -v "$(pwd)_mail-data:/data" -v "$(pwd)/$backup_dir:/backup:ro" alpine sh -c "cd /data && tar xzf /backup/blobs.tgz"

echo "Restore completed from $backup_dir"
