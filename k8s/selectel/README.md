# Selectel Kubernetes

This folder composes the production-like Kubernetes cluster that runs in Selectel.

It uses:

- Kubernetes provider for native Kubernetes objects.
- Helm provider for third-party charts.
- OpenStack provider for Selectel Object Storage buckets.
- S3 backend for OpenTofu state.

## Architecture

```mermaid
flowchart TB
  tofu[OpenTofu in k8s/selectel] --> kubeProvider[Kubernetes provider]
  tofu --> helmProvider[Helm provider]
  tofu --> openstackProvider[OpenStack provider]

  kubeProvider --> kube[Kubernetes API]
  helmProvider --> kube
  openstackProvider --> s3[Selectel Object Storage]

  kube --> namespaces[Namespaces]
  kube --> ingress[Ingresses]
  kube --> secrets[Secrets]
  kube --> jobs[Jobs / CronJobs]

  helmProvider --> nginx[ingress-nginx]
  helmProvider --> cert[cert-manager]
  helmProvider --> cnpg[CloudNativePG]
  helmProvider --> grafana[Grafana / Loki / Alloy]
  helmProvider --> jenkins[Jenkins]

  s3 --> tfstate[OpenTofu state]
  s3 --> backups[Backups, dumps, logs]
```

## Entry Point

Main files:

- `main.tf` - providers, modules, namespaces, ingresses, and cluster composition.
- `variables.tf` - required configuration.
- `outputs.tf` - generated endpoints and credentials.
- `terraform.tfvars.example` - non-secret example values.
- `secret.backend.tfvars.example` - backend credentials example.

Initialize:

```powershell
cd k8s/selectel
tofu init -backend-config=secret.backend.tfvars
```

Plan:

```powershell
tofu plan
```

Apply:

```powershell
tofu apply
```

## Selectel-Specific Details

Region:

```text
ru-7
```

S3 endpoint:

```text
https://s3.ru-7.storage.selcloud.ru
```

Storage class used by stateful workloads:

```text
fast.ru-7a
universal2.ru-7a
```

Storage usage:

```mermaid
flowchart LR
  fast[fast.ru-7a block storage] --> pgData[PostgreSQL data PVCs]
  fast --> pgWal[PostgreSQL WAL PVCs]
  fast --> wordpress[WordPress and MariaDB PVCs]
  fast --> grafana[Grafana PVC]
  fast --> jenkins[Jenkins PVC]

  object[Selectel S3] --> tfstate[OpenTofu state]
  object --> pgPhysical[PostgreSQL physical backups]
  object --> pgDumps[PostgreSQL logical dumps]
  object --> wpBackups[Public site backups]
  object --> loki[Loki log chunks and index]
  object --> frontend[Frontend static assets]
```

OpenTofu state is stored in Selectel S3 with path-style addressing and validation skips required for S3-compatible storage.

### Dev, feature, and release database storage migration

`dev-db-storage-migration.tf`, `feature-db-storage-migration.tf`, and
`release-db-storage-migration.tf` implement staged, rollback-preserving
migrations from Fast volumes to 400 GiB Universal v2 volumes. Universal v2 is
provisioned with the Selectel default of 2,000 IOPS.

Use `dev_db_storage_migration_stage`,
`feature_db_storage_migration_stage`, or
`release_db_storage_migration_stage` for the corresponding stand:

| Stage | Effect |
| --- | --- |
| `disabled` | No migration resources. |
| `copy` | Creates the protected Universal PVC and runs one online `pg_basebackup`. |
| `replicate` | Removes the completed copy Job and starts the new database as a streaming standby. |
| `cutover` | Scales the old StatefulSet to zero and moves the stable database Services to the promoted Universal instance. |
| `complete` | Keeps the post-cutover topology after validation. |

`complete` is the repository default after each completed cutover. In this
stage the old direct PostgreSQL StatefulSet is removed while its retention
policy leaves the Fast PVC available for the explicit final deletion step.

Before `copy`, PostgreSQL must allow the `aof` replication role from the
cluster pod CIDR. Do not use a public or unrestricted CIDR.

Before applying `cutover`:

1. Scale the corresponding application to zero.
2. Confirm the standby replay LSN equals the primary LSN.
3. Scale the old database StatefulSet to zero and wait for it to stop.
4. Promote the Universal standby and confirm it is writable.
5. Apply the `cutover` stage, validate the stable Service, then restore the
   application replica count.

The old Fast PVC is deliberately retained. It is a lossless rollback point
until application writes resume on Universal; after that, rolling back requires
reconciling post-cutover writes. Delete the Fast PVC separately after the
agreed validation window. Billing does not decrease while both volumes exist.

Provider docs:

- Selectel Object Storage S3 API: <https://docs.selectel.ru/cloud/object-storage/>
- OpenStack Terraform provider: <https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs>
- Kubernetes provider: <https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs>
- Helm provider: <https://registry.terraform.io/providers/hashicorp/helm/latest/docs>

## Cluster Add-ons

The following platform modules are installed:

- `ingress-nginx` - public HTTP/HTTPS traffic.
- `cert-manager` - TLS certificates.
- `cloudnative-pg-operator` - PostgreSQL operator.
- `jenkins` - CI/CD jobs.
- `observability` - Grafana, Loki, Alloy.

Check platform namespaces:

```powershell
kubectl get ns ingress-nginx,cert-manager,cnpg-system,jenkins,observability
kubectl -n ingress-nginx get pods,svc
kubectl -n cert-manager get pods
kubectl -n cnpg-system get pods
```

## AOF Environments

The cluster has three application environments:

| Environment | Namespace | Public host | PostgreSQL cluster |
| --- | --- | --- | --- |
| dev | `aof-dev` | `dev.k8s.zazer.fun` | `aof-dev-db` |
| feature | `aof-feature` | `feature.k8s.zazer.fun` | `aof-feature-db` |
| release | `aof-release` | `release.k8s.zazer.fun` | `aof-release-db` |

Each namespace includes:

- PostgreSQL with CloudNativePG;
- frontend gateway;
- registry pull secret for backend images;
- ingress for the frontend host.

Environment internals:

```mermaid
flowchart TB
  subgraph env[aof-* namespace]
    ingress[Ingress host] --> frontendSvc[frontend-gateway Service]
    frontendSvc --> frontend[frontend-gateway Deployment]
    frontend --> frontendS3[Frontend S3 bucket]

    backend[aof-back Deployment from Jenkins] --> pg[PostgreSQL cluster]
    pg --> pgPVC[Data + WAL PVCs]
    pg --> pgBackups[S3 physical backups]
    pgDump[Logical dump CronJob] --> pg
    pgDump --> dumpS3[S3 logical dumps]
  end
```

## Kayra Replacement Rollout

Keep `legacy_runtime_services_enabled = true` for the first infrastructure apply. This updates Jenkins, direct PostgreSQL capacity, and dual-host ingress without stopping services used by the old backend image.

Deploy and verify the current `develop` backend in `dev`, `feature`, and `release`. After all three deployments are healthy and logs contain no Redis, RabbitMQ, Ignite, or PgBouncer connection attempts, set:

```hcl
legacy_runtime_services_enabled = false
```

Review the plan and apply it to remove the unused services. The removal plan must not contain PostgreSQL clusters, PVCs, namespaces, frontend gateways, Jenkins, ingress-nginx, or observability resources.

Before restoring Kayra data or switching production DNS:

- size each PostgreSQL data PVC for its source database plus migration and vacuum headroom;
- resize the application node pool for measured Kayra JVM memory, then update the chart resource requests and limits;
- restore production-like data and complete player, WebSocket, scheduler, and load tests;
- provision each `*-zazer-fun-tls` secret before DNS cutover, using DNS-01 or an approved transfer of the existing certificate;
- keep Kayra available until post-cutover checks and rollback validation pass.

Observed during migration planning: Kayra databases were approximately 242 GB and 285 GB, while stand PVCs were 20 GiB. Kayra's largest Tomcat process used approximately 38 GiB RSS, while the Kubernetes compute nodes exposed approximately 6 GiB each. These values must be measured again immediately before capacity changes.

Inspect one environment:

```powershell
kubectl -n aof-feature get pods,svc,ingress,pvc,secret
kubectl -n aof-feature get cluster,backup,scheduledbackup
```

## PostgreSQL Backups

Automatic PostgreSQL backups are suspended for the `dev`, `feature`, and
`release` stands because their databases are disposable copies of production.
The logical backup CronJobs are retained and can still be triggered manually
when backup or restore behavior needs to be tested.

The PostgreSQL module supports:

- physical backups and WAL archive through CloudNativePG;
- logical `pg_dump -Fc` backups through a Kubernetes CronJob.

The physical backup bucket is exposed by:

```powershell
tofu output postgres_backup_bucket
```

The logical dump bucket is exposed by:

```powershell
tofu output postgres_dump_bucket
```

Automatic logical dumps use paths like:

```text
dev/automatic/
feature/automatic/
release/automatic/
```

Manual dumps use paths like:

```text
dev/manual/
feature/manual/
release/manual/
```

Backup purpose:

```mermaid
flowchart LR
  physical[Physical backups + WAL] --> disaster[Cluster recovery]
  logical[Logical pg_dump files] --> manual[Manual restore / data transfer / debugging]
```

## Public Sites

Namespace:

```text
public-sites
```

Sites:

| Module key | Hosts | Purpose |
| --- | --- | --- |
| `l-zazer` | `l.zazer.mobi` | landing WordPress site |
| `hitmakers` | `hitmakers.games`, `hitmakers.website` | official public site |

The `l-zazer` landing accepts files up to 128 MiB. Its PHP ConfigMap sets
`upload_max_filesize=128M`, `post_max_size=144M`, and `memory_limit=256M`;
the ingress allows 144 MiB requests to leave room for multipart overhead.
The ConfigMap is mounted at `/usr/local/etc/php/conf.d/zz-uploads.ini`, and
a checksum in the pod template triggers a rollout when it changes.
Configure this through `upload_max_filesize_mb` in the public site map.
Other sites retain the image's PHP defaults when this value is null.
The landing uses `wordpress_update_strategy = "Recreate"` because its files
PVC cannot attach to multiple nodes. Updates briefly interrupt service while
the old pod stops and the replacement attaches the disk.

Resources per site:

- MariaDB StatefulSet and PVC;
- WordPress Deployment and files PVC;
- Service for MariaDB;
- Service for WordPress;
- Ingress with cert-manager TLS;
- daily backup CronJob at `03:00 Europe/Moscow`;
- suspended restore CronJob for manual restore from S3.

Public sites map:

```mermaid
flowchart TB
  subgraph public[public-sites namespace]
    lIngress[l.zazer.mobi Ingress] --> lWp[l-zazer WordPress]
    hIngress[hitmakers.games / hitmakers.website Ingress] --> hWp[hitmakers WordPress]

    lWp --> lFiles[l-zazer files PVC]
    lWp --> lDb[l-zazer MariaDB]
    lDb --> lDbPVC[l-zazer DB PVC]

    hWp --> hFiles[hitmakers files PVC]
    hWp --> hDb[hitmakers MariaDB]
    hDb --> hDbPVC[hitmakers DB PVC]

    lBackup[l-zazer backup CronJob] --> publicS3[Public sites backup S3 bucket]
    hBackup[hitmakers backup CronJob] --> publicS3
    publicS3 --> lRestore[l-zazer restore CronJob, suspended]
    publicS3 --> hRestore[hitmakers restore CronJob, suspended]
  end
```

Public site backup bucket:

```powershell
tofu output public_sites_backup_s3_bucket
```

Backup prefixes:

```text
l-zazer-mobi/
hitmakers-copy/
```

## Observability

Namespace:

```text
observability
```

Public URL:

```text
https://grafana.k8s.zazer.fun
```

Get Grafana admin credentials:

```powershell
tofu output -raw grafana_admin_username
tofu output -raw grafana_admin_password
```

Loki stores log chunks and indexes in Selectel S3. Grafana stores its own UI state on a `fast.ru-7a` PVC.

Kubernetes pod logs are collected by the Alloy DaemonSet from selected namespaces.

Dedicated servers push logs through:

```text
https://grafana.k8s.zazer.fun/loki/api/v1/push
```

Get dedicated-server credentials:

```powershell
tofu output -raw dedicated_logs_basic_auth_username
tofu output -raw dedicated_logs_basic_auth_password
```

Observability request and ingest flow:

```mermaid
flowchart TB
  browser[Browser] --> grafanaIngress[grafana.k8s.zazer.fun Ingress]
  grafanaIngress --> grafana[Grafana Service]
  grafana --> loki[Loki Service]

  podLogs[Kubernetes pod logs] --> alloy[Alloy DaemonSet]
  alloy --> loki

  dedicated[Dedicated server Alloy] --> pushIngress[/loki/api/v1/push Ingress]
  pushIngress --> auth[nginx basic auth]
  auth --> gateway[Alloy gateway]
  gateway --> loki

  loki --> s3[Loki S3 bucket]
```

## Public Ingresses

Important public hosts:

- `dev.k8s.zazer.fun`
- `feature.k8s.zazer.fun`
- `release.k8s.zazer.fun`
- `grafana.k8s.zazer.fun`
- Jenkins host from `var.jenkins_host`
- `l.zazer.mobi`
- `hitmakers.games`
- `hitmakers.website`

Inspect:

```powershell
kubectl get ingress -A
kubectl get certificate -A
```

## Outputs

Common outputs:

```powershell
tofu output
tofu output aof_back_hosts
tofu output public_sites_ingresses
tofu output dedicated_logs_push_url
```

Sensitive outputs:

```powershell
tofu output -raw jenkins_admin_password
tofu output -raw grafana_admin_password
tofu output -raw dedicated_logs_basic_auth_password
```

Do not paste sensitive output into tickets or shared chats.

## Troubleshooting Selectel Issues

PVC pending:

```powershell
kubectl get storageclass
kubectl -n <namespace> describe pvc <pvc>
```

Ingress has no external address:

```powershell
kubectl -n ingress-nginx get svc
kubectl -n ingress-nginx describe svc ingress-nginx-controller
```

Certificate not ready:

```powershell
kubectl get certificate,certificaterequest,order,challenge -A
kubectl -n cert-manager logs deploy/cert-manager --tail=100
```

Object storage errors:

- verify endpoint is `https://s3.ru-7.storage.selcloud.ru`;
- verify region is `ru-7`;
- use path-style mode with S3-compatible clients;
- check access key and secret key from the intended Selectel project.

Helm repository cache errors on Windows:

```powershell
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

Then rerun:

```powershell
tofu plan
```
