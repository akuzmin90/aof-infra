# AOF Infrastructure

This repository contains infrastructure for local development and future cloud deployment.

The current local setup runs a production-like Kubernetes environment on Windows with kind. It is intended for testing cluster internals, Jenkins jobs, S3-style frontend hosting, PostgreSQL, and the backend Helm chart before enabling the same patterns in Selectel.

## Local Kind Cluster On Windows

### What This Creates

The local kind setup creates:

- kind Kubernetes cluster named `aof`
- kube context `kind-aof`
- ingress-nginx on local ports `80` and `443`
- locally trusted TLS with `mkcert`
- Jenkins at `https://jenkins.hitmakers.ru`
- MinIO S3-compatible storage at `https://s3.hitmakers.ru`
- frontend gateway at `https://dev.hitmakers.ru`
- CloudNativePG PostgreSQL cluster
- PostgreSQL dump and restore Jenkins jobs
- frontend Jenkins job that builds `aof-front` and uploads `dist/` to MinIO
- backend Helm chart support from `../aof-back/chart`

Argo CD may also be installed by the current kind Terraform root, but Jenkins is the active deployment path for now.

### Prerequisites

Install these on Windows:

- Docker Desktop
- kubectl
- kind
- OpenTofu
- Helm
- mkcert
- Git

Check from PowerShell:

```powershell
docker version
kubectl version --client
kind version
tofu version
helm version
mkcert -version
git --version
```

Docker Desktop must be running before creating the kind cluster.

### Create The Cluster

Run from the repository root:

```powershell
kind create cluster --config k8s/kind/kind-aof.yaml
```

Verify:

```powershell
kubectl config current-context
kubectl --context kind-aof get nodes
```

Expected:

- one control-plane node
- two worker nodes
- context `kind-aof`

If you need to recreate the cluster:

```powershell
kind delete cluster --name aof
kind create cluster --config k8s/kind/kind-aof.yaml
```

### Configure Local DNS And TLS

Install the local CA:

```powershell
mkcert -install
```

Generate local certificates:

```powershell
cd k8s/kind
New-Item -ItemType Directory -Force .local-certs
mkcert `
  -cert-file .local-certs/hitmakers.local.pem `
  -key-file .local-certs/hitmakers.local-key.pem `
  argocd.hitmakers.ru `
  dev.hitmakers.ru `
  jenkins.hitmakers.ru `
  s3.hitmakers.ru
cd ../..
```

Edit this file as Administrator:

```text
C:\Windows\System32\drivers\etc\hosts
```

Add:

```text
127.0.0.1 argocd.hitmakers.ru
127.0.0.1 dev.hitmakers.ru
127.0.0.1 jenkins.hitmakers.ru
127.0.0.1 s3.hitmakers.ru
```

Ports `80` and `443` must be free on Windows. If kind cannot start ingress, check IIS, local nginx, other proxies, or another kind cluster.

### Install Cluster Infrastructure

The kind Terraform root uses local state:

```hcl
backend "local" {
  path = "terraform.tfstate"
}
```

Apply it:

```powershell
cd k8s/kind
tofu init
tofu apply
cd ../..
```

Check the main namespaces:

```powershell
kubectl --context kind-aof get ns
kubectl --context kind-aof -n ingress-nginx get pods
kubectl --context kind-aof -n jenkins get pods
kubectl --context kind-aof -n minio get pods
kubectl --context kind-aof -n database get pods
```

### Access Jenkins

Get the admin password:

```powershell
cd k8s/kind
tofu output -raw jenkins_admin_password
cd ../..
```

Open:

```text
https://jenkins.hitmakers.ru
```

Login:

```text
username: admin
password: output from tofu
```

The local Jenkins module creates jobs including:

- `aof-front-local-s3`
- `aof-back-local-k8s`
- `aof-db-dump-manual`
- `aof-db-restore-dev`

### Configure GitHub Credentials In Jenkins

Create Jenkins credentials for GitHub:

```text
Kind: Username with password
Username: x-access-token
Password: GitHub token
ID: github-aof-token
```

Use this credential ID in frontend/backend jobs when cloning private repositories.

Do not put GitHub tokens directly in Git URLs.

### Access MinIO

Open:

```text
https://s3.hitmakers.ru
```

Login:

```text
username: minioadmin
password: minioadmin123
```

Important local buckets:

- `aof-front`
- `aof-postgres-backups`
- `aof-postgres-dumps`

### Deploy Frontend To Local S3

The frontend flow is:

```text
Jenkins -> build aof-front -> upload dist/ to MinIO -> frontend gateway -> https://dev.hitmakers.ru
```

Run Jenkins job:

```text
aof-front-local-s3
```

Typical parameters:

```text
BRANCH=master
GIT_CREDENTIALS_ID=github-aof-token
BUILD_COMMAND=npm run build
```

After the job succeeds, open:

```text
https://dev.hitmakers.ru
```

### Local PostgreSQL

PostgreSQL is managed by CloudNativePG in namespace `database`.

Check it:

```powershell
kubectl --context kind-aof -n database get pods,svc,cluster,database,scheduledbackup,backup,pooler
```

Useful connection values:

```powershell
cd k8s/kind
tofu output postgres_jdbc_url
tofu output postgres_username
tofu output -raw postgres_password
cd ../..
```

The backend uses:

```text
jdbc:postgresql://aof-db-rw.database.svc.cluster.local:5432/aof
```

Manual logical dumps and dev restores are handled by Jenkins jobs:

- `aof-db-dump-manual`
- `aof-db-restore-dev`

### Deploy Backend Locally

The backend app repo must exist next to this repo:

```text
../aof-back
```

Build the image from the infra repo root:

```powershell
docker build -t aof-back:local ..\aof-back
```

Load it into kind:

```powershell
kind load docker-image aof-back:local --name aof
```

Deploy with Helm:

```powershell
cd k8s/kind
$pgPassword = tofu output -raw postgres_password
helm upgrade --install aof-back ..\..\..\aof-back\chart `
  --namespace aof `
  --create-namespace `
  --set image.repository=aof-back `
  --set image.tag=local `
  --set image.pullPolicy=Never `
  --set-string database.password=$pgPassword `
  --set ingress.enabled=true
cd ../..
```

The chart deploys:

- `aof-back` Deployment, one replica by default
- `aof-back` Service on port `8888`
- optional ingress path `/api` on `dev.hitmakers.ru`
- local single-node Ignite service used by the backend cache

Verify:

```powershell
kubectl --context kind-aof -n aof get pods,svc,ingress
curl.exe -k -i https://dev.hitmakers.ru/api/
```

Expected API result for unauthenticated access:

```text
HTTP/1.1 401
```

That means the backend is reachable and security is rejecting anonymous API access.

### Backend Jenkins Job

The job is:

```text
aof-back-local-k8s
```

It is designed for the production-shaped flow:

```text
checkout aof-back -> build image -> push image to registry -> helm upgrade --install
```

For real Jenkins backend deployment, provide:

```text
GIT_CREDENTIALS_ID=github-aof-token
REGISTRY_SERVER=<registry host>
REGISTRY_CREDENTIALS_ID=<Jenkins registry credentials>
IMAGE_REPOSITORY=<full image repo, for example cr.selcloud.ru/aof-registry/aof-back>
```

For pure local kind testing without a registry, use the manual `docker build` and `kind load docker-image` flow above.

### Verify End To End

Check infrastructure:

```powershell
kubectl --context kind-aof -n ingress-nginx get pods
kubectl --context kind-aof -n jenkins get pods
kubectl --context kind-aof -n minio get pods
kubectl --context kind-aof -n database get pods
kubectl --context kind-aof -n aof get pods
```

Check browser URLs:

```text
https://jenkins.hitmakers.ru
https://s3.hitmakers.ru
https://dev.hitmakers.ru
```

Check backend ingress:

```powershell
curl.exe -k -i https://dev.hitmakers.ru/api/
```

Expected:

```text
HTTP/1.1 401
```

### Troubleshooting

If `tofu apply` cannot create ingresses or the kind cluster cannot start, check that Windows ports `80` and `443` are free.

If browsers do not trust local TLS, rerun:

```powershell
mkcert -install
```

Then regenerate certs in `k8s/kind/.local-certs` and rerun:

```powershell
cd k8s/kind
tofu apply
cd ../..
```

If `dev.hitmakers.ru`, `jenkins.hitmakers.ru`, or `s3.hitmakers.ru` do not resolve, re-check the Windows hosts file.

If `aof-back` is stuck on Liquibase lock after interrupted startup:

```powershell
kubectl --context kind-aof -n aof scale deployment/aof-back --replicas=0
$encoded = kubectl --context kind-aof -n database get secret aof-db-app -o jsonpath='{.data.password}'
$pgPassword = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
kubectl --context kind-aof -n database exec aof-db-1 -- env PGPASSWORD=$pgPassword psql -h aof-db-rw.database.svc.cluster.local -U aof -d aof -c "UPDATE databasechangeloglock SET locked=false, lockgranted=NULL, lockedby=NULL WHERE id=1;"
kubectl --context kind-aof -n aof scale deployment/aof-back --replicas=1
```

If `aof-back` returns `401` on `/api/`, that is expected for anonymous requests.

### Delete Local Cluster

```powershell
kind delete cluster --name aof
```

Local Terraform state lives in:

```text
k8s/kind/terraform.tfstate
```

Do not commit local state files.
