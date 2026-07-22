# AOF Backend Helm Chart

This chart deploys the existing AOF backend Docker image without changing application behavior.

The runtime intentionally uses:

- one replica;
- the `dev` Spring profile used by Kayra;
- the application's existing scheduler behavior;
- the existing embedded WebSocket broker and cache behavior;
- PostgreSQL configured through environment variables;
- `Recreate` deployment strategy so old and new pods never run together.

The chart does not deploy or enable PgBouncer, RabbitMQ, Redis, Ignite, HPA, or application-level HA. It does not override the application's existing Hikari or Liquibase settings.

## Validate

```bash
helm lint chart --set-string database.password=lint-only
helm template aof-back chart \
  --namespace aof-dev \
  --set image.repository=registry.example/aof-back \
  --set image.tag=test \
  --set-string database.password=lint-only
```

## Jenkins Deploy

```bash
helm upgrade --install aof-back chart \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set image.repository="$IMAGE_REPOSITORY" \
  --set image.tag="$IMAGE_TAG" \
  --set image.pullPolicy=IfNotPresent \
  --set springProfile=dev \
  --set database.url="$DATABASE_URL" \
  --set-string database.username="$DATABASE_USERNAME" \
  --set-string database.password="$DATABASE_PASSWORD" \
  --atomic \
  --wait \
  --timeout 15m
```

Prefer `database.existingSecret` instead of passing credentials to Helm when the target namespace already contains a compatible Secret.
