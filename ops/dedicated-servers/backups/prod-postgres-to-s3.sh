#!/usr/bin/env bash
set -euo pipefail

# Production PostgreSQL logical backup to Selectel S3.
#
# Required environment variables:
#   S3_ACCESS_KEY
#   S3_SECRET_KEY
#
# Optional environment variables:
#   S3_ENDPOINT   default: https://s3.ru-7.storage.selcloud.ru
#   S3_BUCKET     default: aof-postgres-dumps
#   S3_PREFIX     default: prod/automatic
#   PGHOST        default: 127.0.0.1
#   PGPORT        default: 5432
#   PGUSER        default: aof
#   PGDATABASE    default: aof
#   PGPASSWORD    default: aof

S3_ENDPOINT="${S3_ENDPOINT:-https://s3.ru-7.storage.selcloud.ru}"
S3_BUCKET="${S3_BUCKET:-aof-postgres-dumps}"
S3_PREFIX="${S3_PREFIX:-prod/automatic}"

PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-aof}"
PGDATABASE="${PGDATABASE:-aof}"
PGPASSWORD="${PGPASSWORD:-aof}"

BACKUP_FILE="/tmp/aof-prod-backup.sql.gz"
TS="$(date +"%Y-%m-%d-%H%M%S")"
OBJECT_NAME="aof-prod-$TS.sql.gz"

: "${S3_ACCESS_KEY:?Missing S3_ACCESS_KEY}"
: "${S3_SECRET_KEY:?Missing S3_SECRET_KEY}"

export PGPASSWORD

cleanup() {
  rm -f "$BACKUP_FILE"
}
trap cleanup EXIT

pg_dump \
  -U "$PGUSER" \
  -h "$PGHOST" \
  -p "$PGPORT" \
  --exclude-table-data=player_log \
  "$PGDATABASE" \
  | gzip -4 > "$BACKUP_FILE"

gzip -t "$BACKUP_FILE"

mc alias set aof-s3 "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY" --api S3v4 --path on
mc cp "$BACKUP_FILE" "aof-s3/$S3_BUCKET/$S3_PREFIX/$OBJECT_NAME"
mc cp "$BACKUP_FILE" "aof-s3/$S3_BUCKET/$S3_PREFIX/latest.sql.gz"

echo "DONE: s3://$S3_BUCKET/$S3_PREFIX/$OBJECT_NAME"

