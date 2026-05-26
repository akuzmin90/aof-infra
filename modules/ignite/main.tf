resource "kubernetes_config_map" "ignite" {
  metadata {
    name      = "ignite-config"
    namespace = "aof"
  }

  data = {
    "ignite.xml" = <<-XML
      <?xml version="1.0" encoding="UTF-8"?>
      <beans xmlns="http://www.springframework.org/schema/beans"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="
               http://www.springframework.org/schema/beans
               http://www.springframework.org/schema/beans/spring-beans.xsd">
        <bean class="org.apache.ignite.configuration.IgniteConfiguration">
          <property name="peerClassLoadingEnabled" value="false"/>
          <property name="metricsLogFrequency" value="0"/>
        </bean>
      </beans>
    XML
  }
}

resource "kubernetes_deployment" "ignite" {
  metadata {
    name      = "ignite"
    namespace = "aof"

    labels = {
      app = "ignite"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "ignite"
      }
    }

    template {
      metadata {
        labels = {
          app = "ignite"
        }
      }

      spec {
        container {
          name              = "ignite"
          image             = "apacheignite/ignite:2.17.0"
          image_pull_policy = "IfNotPresent"

          env {
            name  = "CONFIG_URI"
            value = "file:/ignite/config/ignite.xml"
          }

          env {
            name  = "IGNITE_QUIET"
            value = "false"
          }

          env {
            name  = "JVM_OPTS"
            value = "-Xms512m -Xmx768m -Djava.net.preferIPv4Stack=true --add-opens=java.base/jdk.internal.access=ALL-UNNAMED --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.base/sun.util.calendar=ALL-UNNAMED --add-opens=java.management/com.sun.jmx.mbeanserver=ALL-UNNAMED --add-opens=java.base/sun.reflect.generics.reflectiveObjects=ALL-UNNAMED --add-opens=jdk.management/com.sun.management.internal=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.util.concurrent=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.locks=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-opens=java.base/java.math=ALL-UNNAMED --add-opens=java.sql/java.sql=ALL-UNNAMED"
          }

          port {
            name           = "discovery"
            container_port = 47500
          }

          port {
            name           = "communication"
            container_port = 47100
          }

          port {
            name           = "thin-client"
            container_port = 10800
          }

          volume_mount {
            name       = "config"
            mount_path = "/ignite/config"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }

            limits = {
              cpu    = "1"
              memory = "1024Mi"
            }
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map.ignite.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "ignite" {
  metadata {
    name      = "ignite"
    namespace = "aof"
  }

  spec {
    selector = {
      app = "ignite"
    }

    port {
      name        = "discovery"
      port        = 47500
      target_port = "discovery"
    }

    port {
      name        = "communication"
      port        = 47100
      target_port = "communication"
    }

    port {
      name        = "thin-client"
      port        = 10800
      target_port = "thin-client"
    }
  }
}
