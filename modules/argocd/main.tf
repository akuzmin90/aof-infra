resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.5.12"

  values = [
    yamlencode({
      global = {
        logging = {
          format = "json"
        }
      }

      controller = {
        metrics = {
          enabled = true
        }
      }

      server = {
        replicas = 2

        service = {
          type = "ClusterIP"
        }

        ingress = {
          enabled = false
        }

        metrics = {
          enabled = true
        }
      }

      repoServer = {
        replicas = 2

        metrics = {
          enabled = true
        }
      }

      applicationSet = {
        replicas = 2

        metrics = {
          enabled = true
        }
      }

      notifications = {
        enabled = true

        metrics = {
          enabled = true
        }
      }

      configs = {
        cm = {
          "timeout.reconciliation" = "180s"
        }

        params = {
          "server.insecure" = "false"
        }

        rbac = {
          "policy.default" = "role:readonly"
        }
      }
    })
  ]
}
