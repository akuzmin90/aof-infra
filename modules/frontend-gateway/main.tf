resource "kubernetes_namespace" "frontend" {
  metadata {
    name = "frontend"
  }
}

resource "kubernetes_config_map" "nginx" {
  metadata {
    name      = "frontend-gateway-nginx"
    namespace = kubernetes_namespace.frontend.metadata[0].name
  }

  data = {
    "default.conf" = <<-EOT
      server {
        listen 8080;
        server_name dev.hitmakers.ru;

        proxy_intercept_errors on;

        location = /nginx-health {
          access_log off;
          return 200 "ok\n";
        }

        location = / {
          proxy_pass http://minio.minio.svc.cluster.local:9000/aof-front/index.html;
          proxy_set_header Host minio.minio.svc.cluster.local;
        }

        location / {
          proxy_pass http://minio.minio.svc.cluster.local:9000/aof-front$request_uri;
          proxy_set_header Host minio.minio.svc.cluster.local;
          error_page 404 = /index.html;
        }
      }
    EOT
  }
}

resource "kubernetes_deployment" "frontend" {
  metadata {
    name      = "frontend-gateway"
    namespace = kubernetes_namespace.frontend.metadata[0].name

    labels = {
      app = "frontend-gateway"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "frontend-gateway"
      }
    }

    template {
      metadata {
        labels = {
          app = "frontend-gateway"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:1.29-alpine"

          port {
            name           = "http"
            container_port = 8080
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/nginx/conf.d/default.conf"
            sub_path   = "default.conf"
          }

          readiness_probe {
            http_get {
              path = "/nginx-health"
              port = "http"
            }
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map.nginx.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend" {
  metadata {
    name      = "frontend-gateway"
    namespace = kubernetes_namespace.frontend.metadata[0].name
  }

  spec {
    selector = {
      app = "frontend-gateway"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }
  }
}
