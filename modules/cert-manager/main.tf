resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

locals {
  cluster_issuer_name = "letsencrypt-prod"
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  repository = "oci://quay.io/jetstack/charts"
  chart      = "cert-manager"
  version    = "v1.19.1"

  set {
    name  = "crds.enabled"
    value = "true"
  }
}

resource "kubernetes_manifest" "letsencrypt_cluster_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"

    metadata = {
      name = local.cluster_issuer_name
    }

    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"

        privateKeySecretRef = {
          name = local.cluster_issuer_name
        }

        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [
    helm_release.cert_manager
  ]
}
