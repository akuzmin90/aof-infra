# Kubernetes Infrastructure

This folder contains Kubernetes environment entrypoints. Reusable resource definitions live in `../modules`; the folders under `k8s` compose those modules for a concrete cluster.

## Big Picture

```mermaid
flowchart TB
  user[Users / browsers] --> dns[DNS]
  dns --> ingress[ingress-nginx]

  ingress --> appdev[dev.k8s.zazer.fun]
  ingress --> appfeature[feature.k8s.zazer.fun]
  ingress --> apprelease[release.k8s.zazer.fun]
  ingress --> grafanaHost[grafana.k8s.zazer.fun]
  ingress --> publicSites[public WordPress sites]
  ingress --> jenkinsHost[Jenkins]

  subgraph aof[AOF namespaces]
    appdev --> dev[aof-dev]
    appfeature --> feature[aof-feature]
    apprelease --> release[aof-release]
    dev --> devDeps[Redis / Ignite / RabbitMQ / PostgreSQL / frontend gateway]
    feature --> featureDeps[Redis / Ignite / RabbitMQ / PostgreSQL / frontend gateway]
    release --> releaseDeps[Redis / Ignite / RabbitMQ / PostgreSQL / frontend gateway]
  end

  subgraph obs[observability]
    grafanaHost --> grafana[Grafana]
    grafana --> loki[Loki]
    alloy[Alloy DaemonSet] --> loki
    gateway[Alloy gateway] --> loki
  end

  subgraph public[public-sites]
    publicSites --> wordpress[WordPress deployments]
    wordpress --> mariadb[MariaDB StatefulSets]
  end

  subgraph cicd[jenkins]
    jenkinsHost --> jenkins[Jenkins]
    jenkins --> frontendS3[Frontend S3 buckets]
    jenkins --> registry[Container registry]
    jenkins --> aof
  end

  subgraph storage[Selectel storage]
    loki --> lokiS3[Loki S3 bucket]
    devDeps --> pgS3[PostgreSQL backup/dump S3 buckets]
    featureDeps --> pgS3
    releaseDeps --> pgS3
    wordpress --> wpS3[Public sites backup S3 bucket]
  end
```

## Folders

- `kind/` - local Kubernetes cluster for testing cluster components on a developer machine.
- `selectel/` - production-like Selectel Kubernetes cluster managed with OpenTofu.

Cloud resources that are not Kubernetes objects, such as Selectel S3 buckets, belong under `../cloud`.

## Tooling

Required day-to-day tools:

- `kubectl` - inspect and operate Kubernetes resources.
- `tofu` - apply infrastructure from this repo.
- `helm` - inspect Helm releases and test chart behavior.

Useful docs:

- Kubernetes concepts: <https://kubernetes.io/docs/concepts/>
- kubectl cheat sheet: <https://kubernetes.io/docs/reference/kubectl/cheatsheet/>
- OpenTofu CLI: <https://opentofu.org/docs/cli/>
- Helm docs: <https://helm.sh/docs/>

## Resource Model

We use these basic Kubernetes resources:

- `Namespace` - isolation boundary for one environment or platform component.
- `Deployment` - stateless pods, for example frontend gateway, Grafana, Jenkins, WordPress.
- `StatefulSet` - stateful pods with stable storage, for example MariaDB for WordPress.
- `Service` - stable in-cluster DNS and load balancing for pods.
- `Ingress` - public HTTP/HTTPS routing through ingress-nginx.
- `Secret` - credentials such as database passwords, registry credentials, and S3 keys.
- `ConfigMap` - non-secret config, scripts, and generated app configuration.
- `PersistentVolumeClaim` - disk request for stateful workloads.
- `Job` / `CronJob` - one-off and scheduled operations such as backups and restores.

```mermaid
flowchart LR
  ingress[Ingress] --> svc[Service]
  svc --> pods[Pods]
  deploy[Deployment] --> pods
  sts[StatefulSet] --> statefulPods[Stateful Pods]
  statefulPods --> pvc[PersistentVolumeClaim]
  config[ConfigMap] --> pods
  secret[Secret] --> pods
  cron[CronJob] --> job[Job]
  job --> jobPod[Job Pod]
```

Original docs:

- Workloads: <https://kubernetes.io/docs/concepts/workloads/>
- Services and networking: <https://kubernetes.io/docs/concepts/services-networking/>
- ConfigMaps: <https://kubernetes.io/docs/concepts/configuration/configmap/>
- Secrets: <https://kubernetes.io/docs/concepts/configuration/secret/>
- Persistent volumes: <https://kubernetes.io/docs/concepts/storage/persistent-volumes/>
- Jobs: <https://kubernetes.io/docs/concepts/workloads/controllers/job/>
- CronJobs: <https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/>

## Namespaces We Use

Application stands:

- `aof-dev`
- `aof-feature`
- `aof-release`

Platform and support:

- `ingress-nginx` - public ingress controller.
- `cert-manager` - TLS certificate automation.
- `cnpg-system` - CloudNativePG operator.
- `jenkins` - CI/CD.
- `observability` - Grafana, Loki, and Alloy.
- `public-sites` - legacy public WordPress sites.

```mermaid
flowchart TB
  root[Cluster]
  root --> app[AOF environments]
  app --> dev[aof-dev]
  app --> feature[aof-feature]
  app --> release[aof-release]
  root --> platform[Platform]
  platform --> ingress[ingress-nginx]
  platform --> cert[cert-manager]
  platform --> cnpg[cnpg-system]
  platform --> jenkins[jenkins]
  platform --> observability[observability]
  root --> publicSites[public-sites]
```

## Main Components

Application stands:

- Redis, Ignite, RabbitMQ.
- PostgreSQL through CloudNativePG.
- Frontend gateway that serves S3-hosted frontend files.
- `aof-back`, deployed by Jenkins into the selected namespace.

Public sites:

- `l-zazer` WordPress and MariaDB.
- `hitmakers` WordPress and MariaDB.
- Scheduled S3 backups and suspended restore CronJobs.

Observability:

- Grafana for UI and dashboards.
- Loki for log storage.
- Alloy DaemonSet for Kubernetes pod logs.
- Alloy gateway for logs pushed by dedicated servers.

CI/CD:

- Jenkins builds frontend, uploads frontend assets to S3, builds backend images, and deploys backend Helm chart.

## Data And Backup Paths

```mermaid
flowchart LR
  subgraph pg[PostgreSQL]
    pgCluster[CloudNativePG cluster] --> physical[Physical backup + WAL]
    pgCron[Logical pg_dump CronJob] --> logical[Logical dump]
  end

  subgraph wp[Public WordPress]
    wpFiles[WordPress files PVC] --> wpCron[Backup CronJob]
    wpDb[MariaDB DB] --> wpCron
  end

  subgraph logs[Logs]
    podLogs[Kubernetes pod logs] --> alloy[Alloy]
    dedicated[Dedicated servers] --> gateway[Alloy gateway]
    alloy --> loki[Loki]
    gateway --> loki
  end

  physical --> pgBackupS3[PostgreSQL backup S3 bucket]
  logical --> pgDumpS3[PostgreSQL dump S3 bucket]
  wpCron --> wpBackupS3[Public sites backup S3 bucket]
  loki --> lokiS3[Loki S3 bucket]
```

## Management Boundary

Most long-lived Kubernetes resources are managed by OpenTofu from this repo. Avoid editing managed objects manually unless you are debugging an incident and understand the drift it creates.

Good examples of safe read-only operations:

```powershell
kubectl get pods -A
kubectl -n aof-feature describe pod <pod>
kubectl -n observability logs deploy/grafana --tail=100
```

Examples that create Terraform drift:

```powershell
kubectl patch ingress ...
kubectl edit deployment ...
kubectl delete secret ...
```

If a manual change was needed during an incident, port it back to OpenTofu after the incident.

## Common Workflow

Inspect the current cluster:

```powershell
kubectl config current-context
kubectl get nodes -o wide
kubectl get namespaces
kubectl get ingress -A
```

Review infrastructure changes:

```powershell
cd k8s/selectel
tofu plan
```

Apply reviewed changes:

```powershell
cd k8s/selectel
tofu apply
```

Read generated outputs:

```powershell
cd k8s/selectel
tofu output
tofu output -raw grafana_admin_password
```

Use [OPERATIONS.md](./OPERATIONS.md) for debugging commands.
