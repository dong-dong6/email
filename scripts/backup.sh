#!/usr/bin/env sh
set -eu

stamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="${BACKUP_DIR:-./backups/$stamp}"
mkdir -p "$backup_dir"

docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-email}" "${POSTGRES_DB:-email}" > "$backup_dir/postgres.sql"
docker run --rm -v "$(pwd)_mail-data:/data:ro" -v "$(pwd)/$backup_dir:/backup" alpine tar czf /backup/blobs.tgz -C /data .

echo "Backup written to $backup_dir"
