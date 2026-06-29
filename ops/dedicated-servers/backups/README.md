# Dedicated Server Backups

This folder contains scripts for dedicated servers that still run outside Kubernetes.

## Bucket Choice

Use the logical PostgreSQL dump bucket:

```text
aof-postgres-dumps
```

Reason:

- the production script creates a logical `pg_dump` stream;
- `aof-postgres-dumps` is already meant for logical dumps;
- `aof-postgres-backups` is for CloudNativePG physical backups and WAL archive, so mixing plain `pg_dump` files there would be confusing.

Recommended production object prefix:

```text
prod/automatic/
```

That keeps production separate from Kubernetes environment dumps:

```text
dev/automatic/
feature/automatic/
release/automatic/
prod/automatic/
```

## Script

Use:

```text
prod-postgres-to-s3.sh
```

The script uploads:

```text
s3://aof-postgres-dumps/prod/automatic/aof-prod-YYYY-MM-DD-HHMMSS.sql.gz
s3://aof-postgres-dumps/prod/automatic/latest.sql.gz
```

It only creates the PostgreSQL dump and uploads it to S3.
