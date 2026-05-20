resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.13.3"
  values = concat([
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
        }

        publishService = {
          enabled = true
        }
      }
    })
  ], var.values)
}
