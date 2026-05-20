terraform {
  required_version = ">= 1.6.0"

  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-aof"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "kind-aof"
  }
}

module "ingress_nginx" {
  source = "../../modules/ingress-nginx"

  values = [
    yamlencode({
      controller = {
        hostNetwork = true
        dnsPolicy   = "ClusterFirstWithHostNet"

        service = {
          type = "ClusterIP"
        }

        publishService = {
          enabled = false
        }

        extraArgs = {
          "publish-status-address" = "127.0.0.1"
        }

        nodeSelector = {
          "ingress-ready" = "true"
        }

        tolerations = [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Exists"
            effect   = "NoSchedule"
          },
          {
            key      = "node-role.kubernetes.io/master"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]
      }
    })
  ]
}

module "cert_manager" {
  source = "../../modules/cert-manager"
}

resource "random_password" "jenkins_admin" {
  length  = 24
  special = false
}

module "jenkins" {
  source = "../../modules/jenkins"

  admin_password = random_password.jenkins_admin.result
}

module "argocd" {
  source = "../../modules/argocd"
}

module "minio" {
  source = "../../modules/minio"
}

module "frontend_gateway" {
  source = "../../modules/frontend-gateway"

  depends_on = [
    module.minio
  ]
}

locals {
  local_tls_secret_name = "hitmakers-local-tls"
  local_tls_cert_path   = "${path.module}/.local-certs/hitmakers.local.pem"
  local_tls_key_path    = "${path.module}/.local-certs/hitmakers.local-key.pem"
  local_tls_cert_file   = fileexists(local.local_tls_cert_path) ? local.local_tls_cert_path : "${path.module}/README.md"
  local_tls_key_file    = fileexists(local.local_tls_key_path) ? local.local_tls_key_path : "${path.module}/README.md"
}

resource "kubernetes_secret" "argocd_local_tls" {
  metadata {
    name      = local.local_tls_secret_name
    namespace = module.argocd.namespace
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = file(local.local_tls_cert_file)
    "tls.key" = file(local.local_tls_key_file)
  }

  lifecycle {
    precondition {
      condition     = fileexists(local.local_tls_cert_path) && fileexists(local.local_tls_key_path)
      error_message = "Generate local TLS files first: k8s/kind/.local-certs/hitmakers.local.pem and k8s/kind/.local-certs/hitmakers.local-key.pem."
    }
  }
}

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd"
    namespace = module.argocd.namespace

    annotations = {
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["argocd.hitmakers.ru"]
      secret_name = kubernetes_secret.argocd_local_tls.metadata[0].name
    }

    rule {
      host = "argocd.hitmakers.ru"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-server"

              port {
                number = 443
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_secret" "jenkins_local_tls" {
  metadata {
    name      = local.local_tls_secret_name
    namespace = module.jenkins.namespace
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = file(local.local_tls_cert_file)
    "tls.key" = file(local.local_tls_key_file)
  }

  lifecycle {
    precondition {
      condition     = fileexists(local.local_tls_cert_path) && fileexists(local.local_tls_key_path)
      error_message = "Generate local TLS files first: k8s/kind/.local-certs/hitmakers.local.pem and k8s/kind/.local-certs/hitmakers.local-key.pem."
    }
  }
}

resource "kubernetes_ingress_v1" "jenkins" {
  metadata {
    name      = "jenkins"
    namespace = module.jenkins.namespace
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["jenkins.hitmakers.ru"]
      secret_name = kubernetes_secret.jenkins_local_tls.metadata[0].name
    }

    rule {
      host = "jenkins.hitmakers.ru"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "jenkins"

              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_secret" "frontend_local_tls" {
  metadata {
    name      = local.local_tls_secret_name
    namespace = module.frontend_gateway.namespace
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = file(local.local_tls_cert_file)
    "tls.key" = file(local.local_tls_key_file)
  }

  lifecycle {
    precondition {
      condition     = fileexists(local.local_tls_cert_path) && fileexists(local.local_tls_key_path)
      error_message = "Generate local TLS files first: k8s/kind/.local-certs/hitmakers.local.pem and k8s/kind/.local-certs/hitmakers.local-key.pem."
    }
  }
}

resource "kubernetes_ingress_v1" "frontend" {
  metadata {
    name      = "frontend"
    namespace = module.frontend_gateway.namespace
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["dev.hitmakers.ru"]
      secret_name = kubernetes_secret.frontend_local_tls.metadata[0].name
    }

    rule {
      host = "dev.hitmakers.ru"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = module.frontend_gateway.service_name

              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}
