# Local kind Kubernetes

This folder is for a local Kubernetes cluster used to test cluster internals without Selectel:

- ingress-nginx
- cert-manager
- Jenkins
- Argo CD
- app Helm charts, for example `aof-back`

It does not create cloud resources.

## Prerequisites

Install:

- Docker Desktop
- kubectl
- kind
- OpenTofu
- Helm, optional for manual chart testing
- mkcert, for locally trusted TLS certificates

Check:

```powershell
docker version
kubectl version --client
kind version
tofu version
mkcert -version
```

## Create Cluster

Create a basic two-node cluster:

```powershell
kind create cluster --config k8s/kind/kind-aof.yaml
```

If the cluster already exists and you changed `kind-aof.yaml`, recreate it:

```powershell
kind delete cluster --name aof
kind create cluster --config k8s/kind/kind-aof.yaml
```

This creates:

- 1 control-plane node
- 2 worker nodes
- kube context `kind-aof`
- local port `80` mapped into the cluster
- local port `443` mapped into the cluster
- ingress-nginx pinned to the control-plane node that owns those local ports

Check it:

```powershell
kubectl config current-context
kubectl get nodes
```

## Local DNS and TLS

This setup uses local DNS overrides and a locally trusted mkcert certificate.
It lets the browser open local services with production-like hostnames:

```text
https://argocd.hitmakers.ru
https://dev.hitmakers.ru
https://jenkins.hitmakers.ru
```

Install the local mkcert CA:

```powershell
mkcert -install
```

Generate the local TLS certificate:

```powershell
New-Item -ItemType Directory -Force .local-certs
mkcert `
  -cert-file .local-certs/hitmakers.local.pem `
  -key-file .local-certs/hitmakers.local-key.pem `
  argocd.hitmakers.ru `
  dev.hitmakers.ru `
  jenkins.hitmakers.ru
```

Add local DNS overrides to `C:\Windows\System32\drivers\etc\hosts`.
Run your editor as Administrator and add:

```text
127.0.0.1 argocd.hitmakers.ru
127.0.0.1 dev.hitmakers.ru
127.0.0.1 jenkins.hitmakers.ru
```

If Docker cannot create the cluster, check that ports `80` and `443` are not already used by IIS, another nginx, another kind cluster, or another local proxy.

## Install Cluster Add-ons

From this folder:

```powershell
cd k8s/kind
tofu init
tofu apply
```

This installs the reusable modules from `../../modules`.

It also installs a local frontend hosting mock:

- MinIO as an S3-compatible object store
- bucket `aof-front`
- nginx frontend gateway
- ingress host `https://dev.hitmakers.ru`

Terraform state is explicitly local:

```hcl
backend "local" {
  path = "terraform.tfstate"
}
```

## Jenkins Access

Get the generated admin password:

```powershell
tofu output -raw jenkins_admin_password
```

Open:

```text
https://jenkins.hitmakers.ru
```

Login:

```text
username: admin
password: value from tofu output
```

## Argo CD Access

Get the initial admin password:

```powershell
$encoded = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Open:

```text
https://argocd.hitmakers.ru
```

Login:

```text
username: admin
password: value from argocd-initial-admin-secret
```

## Frontend Local S3 Deploy

The local frontend deployment flow is:

```text
Jenkins -> build aof-front -> upload dist/ to MinIO bucket -> nginx gateway -> https://dev.hitmakers.ru
```

The pipeline template is in:

```text
jenkins/pipelines/aof-front-local-s3.Jenkinsfile
```

Best final location is the app repo:

```text
../aof-front/Jenkinsfile
```

The Jenkins job needs GitHub credentials with ID:

```text
github-aof-token
```

The job uploads to:

```text
endpoint: http://minio.minio.svc.cluster.local:9000
bucket:   aof-front
```

After a successful job run, open:

```text
https://dev.hitmakers.ru
```

## Test App Deployment

Build the backend image:

```powershell
docker build -t aof-back:local ..\..\..\aof-back
```

Load it into kind:

```powershell
kind load docker-image aof-back:local --name aof
```

Then deploy the app chart from the app repo, for example:

```powershell
helm upgrade --install aof-back ..\..\..\aof-back\chart `
  --namespace aof `
  --create-namespace `
  --set image.repository=aof-back `
  --set image.tag=local `
  --set image.pullPolicy=Never
```

## Delete Cluster

```powershell
kind delete cluster --name aof
```

Terraform state in this folder is local test state only. Do not commit `terraform.tfstate`.
