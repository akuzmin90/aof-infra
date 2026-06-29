resource "kubernetes_namespace" "observability" {
  metadata {
    name = var.namespace
  }
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

locals {
  namespace_keep_regex = join("|", var.log_namespaces)
  loki_url             = "http://loki:3100"
  loki_dashboard_ds    = "Loki"
  aof_log_namespaces   = ["aof-dev", "aof-feature", "aof-release"]
  kayra_log_envs       = ["dev", "feature", "release"]

  aof_environments_dashboard = {
    uid           = "aof-environments"
    title         = "AOF Environments"
    schemaVersion = 39
    version       = 1
    refresh       = "30s"
    timezone      = "browser"
    tags          = ["aof", "logs", "environments"]
    time = {
      from = "now-1h"
      to   = "now"
    }
    templating = {
      list = [
        {
          name       = "env"
          type       = "custom"
          label      = "Environment"
          query      = join(",", local.aof_log_namespaces)
          current    = { text = "All", value = "$__all" }
          includeAll = true
          multi      = true
          allValue   = join("|", local.aof_log_namespaces)
        }
      ]
    }
    panels = [
      {
        id          = 8
        title       = "Environment Pulse"
        type        = "stat"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 5, w = 8, x = 0, y = 0 }
        fieldConfig = { defaults = { unit = "short", thresholds = { mode = "absolute", steps = [{ color = "green", value = null }, { color = "yellow", value = 250 }, { color = "red", value = 1000 }] } }, overrides = [] }
        options     = { colorMode = "background", graphMode = "area", justifyMode = "auto", orientation = "auto", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, textMode = "auto" }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (namespace) (count_over_time({namespace=~\"$env\"}[5m]))"
            legendFormat = "{{namespace}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 9
        title       = "Log Share"
        type        = "piechart"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 5, w = 8, x = 8, y = 0 }
        fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        options     = { displayLabels = ["name", "percent"], legend = { displayMode = "list", placement = "right", showLegend = true }, pieType = "donut", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, tooltip = { mode = "single", sort = "none" } }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (namespace) (count_over_time({namespace=~\"$env\"}[$__range]))"
            legendFormat = "{{namespace}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 10
        title       = "Error Pressure"
        type        = "gauge"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 5, w = 8, x = 16, y = 0 }
        fieldConfig = { defaults = { min = 0, unit = "short", thresholds = { mode = "absolute", steps = [{ color = "green", value = null }, { color = "yellow", value = 1 }, { color = "red", value = 10 }] } }, overrides = [] }
        options     = { orientation = "auto", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, showThresholdLabels = false, showThresholdMarkers = true }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (namespace) (count_over_time({namespace=~\"$env\"} |~ \"(?i)(error|exception|failed|failure|fatal|panic|timeout)\"[$__range]))"
            legendFormat = "{{namespace}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 11
        title       = "Error Timeline"
        type        = "state-timeline"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 7, w = 24, x = 0, y = 5 }
        fieldConfig = { defaults = { unit = "short", thresholds = { mode = "absolute", steps = [{ color = "green", value = null }, { color = "yellow", value = 1 }, { color = "red", value = 5 }] } }, overrides = [] }
        options     = { alignValue = "left", legend = { displayMode = "list", placement = "bottom", showLegend = true }, mergeValues = true, rowHeight = 0.8, showValue = "auto", tooltip = { mode = "single", sort = "none" } }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (namespace) (count_over_time({namespace=~\"$env\"} |~ \"(?i)(error|exception|failed|failure|fatal|panic|timeout)\"[5m]))"
            legendFormat = "{{namespace}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 1
        title       = "Log Volume By Environment"
        type        = "timeseries"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 8, w = 12, x = 0, y = 12 }
        fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (namespace) (count_over_time({namespace=~\"$env\"}[5m]))"
            legendFormat = "{{namespace}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 2
        title       = "Errors By Environment"
        type        = "timeseries"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 8, w = 12, x = 12, y = 12 }
        fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (namespace) (count_over_time({namespace=~\"$env\"} |~ \"(?i)(error|exception|failed|failure|fatal|panic|timeout)\"[5m]))"
            legendFormat = "{{namespace}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 3
        title       = "Error Count In Selected Range"
        type        = "stat"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 5, w = 8, x = 0, y = 20 }
        fieldConfig = { defaults = { unit = "short", thresholds = { mode = "absolute", steps = [{ color = "green", value = null }, { color = "yellow", value = 1 }, { color = "red", value = 20 }] } }, overrides = [] }
        options     = { colorMode = "background", graphMode = "area", justifyMode = "auto", orientation = "auto", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, textMode = "auto" }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (namespace) (count_over_time({namespace=~\"$env\"} |~ \"(?i)(error|exception|failed|failure|fatal|panic|timeout)\"[$__range]))"
            legendFormat = "{{namespace}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 4
        title       = "Backend Log Volume"
        type        = "stat"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 5, w = 8, x = 8, y = 20 }
        fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        options     = { colorMode = "value", graphMode = "area", justifyMode = "auto", orientation = "auto", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, textMode = "auto" }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (namespace) (count_over_time({namespace=~\"$env\", app=\"aof-back\"}[$__range]))"
            legendFormat = "{{namespace}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 5
        title       = "Noisiest Pods"
        type        = "bargauge"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 5, w = 8, x = 16, y = 20 }
        fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        options     = { displayMode = "gradient", minVizHeight = 10, minVizWidth = 0, namePlacement = "auto", orientation = "horizontal", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, showUnfilled = true, sizing = "auto", valueMode = "color" }
        targets = [
          {
            refId        = "A"
            expr         = "topk(10, sum by (namespace, pod) (count_over_time({namespace=~\"$env\"}[$__range])))"
            legendFormat = "{{namespace}} / {{pod}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id         = 6
        title      = "Recent Error Logs"
        type       = "logs"
        datasource = local.loki_dashboard_ds
        gridPos    = { h = 10, w = 12, x = 0, y = 25 }
        options    = { dedupStrategy = "none", enableLogDetails = true, prettifyLogMessage = false, showCommonLabels = false, showLabels = false, showTime = true, sortOrder = "Descending", wrapLogMessage = true }
        targets = [
          {
            refId      = "A"
            expr       = "{namespace=~\"$env\"} |~ \"(?i)(error|exception|failed|failure|fatal|panic|timeout)\""
            queryType  = "range"
            datasource = local.loki_dashboard_ds
          }
        ]
      },
      {
        id         = 7
        title      = "Recent Backend Logs"
        type       = "logs"
        datasource = local.loki_dashboard_ds
        gridPos    = { h = 10, w = 12, x = 12, y = 25 }
        options    = { dedupStrategy = "none", enableLogDetails = true, prettifyLogMessage = false, showCommonLabels = false, showLabels = false, showTime = true, sortOrder = "Descending", wrapLogMessage = true }
        targets = [
          {
            refId      = "A"
            expr       = "{namespace=~\"$env\", app=\"aof-back\"}"
            queryType  = "range"
            datasource = local.loki_dashboard_ds
          }
        ]
      }
    ]
  }

  dedicated_stands_dashboard = {
    uid           = "dedicated-stands"
    title         = "Dedicated Stands"
    schemaVersion = 39
    version       = 1
    refresh       = "30s"
    timezone      = "browser"
    tags          = ["aof", "logs", "dedicated", "stands"]
    time = {
      from = "now-1h"
      to   = "now"
    }
    templating = {
      list = [
        {
          name       = "env"
          type       = "custom"
          label      = "Stand"
          query      = join(",", local.kayra_log_envs)
          current    = { text = "All", value = "$__all" }
          includeAll = true
          multi      = true
          allValue   = join("|", local.kayra_log_envs)
        },
        {
          name       = "host"
          type       = "custom"
          label      = "Host"
          query      = "kayra"
          current    = { text = "kayra", value = "kayra" }
          includeAll = false
          multi      = false
          hide       = 2
        }
      ]
    }
    panels = [
      {
        id          = 1
        title       = "Stand Pulse"
        type        = "stat"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 5, w = 6, x = 0, y = 0 }
        fieldConfig = { defaults = { unit = "short", thresholds = { mode = "absolute", steps = [{ color = "green", value = null }, { color = "yellow", value = 500 }, { color = "red", value = 2000 }] } }, overrides = [] }
        options     = { colorMode = "background", graphMode = "area", justifyMode = "auto", orientation = "auto", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, textMode = "auto" }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (env) (count_over_time({source=\"dedicated\", host=~\"$host\", env=~\"$env\"}[5m]))"
            legendFormat = "{{env}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 2
        title       = "Stand Share"
        type        = "piechart"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 5, w = 6, x = 6, y = 0 }
        fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        options     = { displayLabels = ["name", "percent"], legend = { displayMode = "list", placement = "right", showLegend = true }, pieType = "donut", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, tooltip = { mode = "single", sort = "none" } }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (env) (count_over_time({source=\"dedicated\", host=~\"$host\", env=~\"$env\"}[$__range]))"
            legendFormat = "{{env}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 3
        title       = "Error Pressure"
        type        = "gauge"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 5, w = 6, x = 12, y = 0 }
        fieldConfig = { defaults = { min = 0, unit = "short", thresholds = { mode = "absolute", steps = [{ color = "green", value = null }, { color = "yellow", value = 1 }, { color = "red", value = 10 }] } }, overrides = [] }
        options     = { orientation = "auto", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, showThresholdLabels = false, showThresholdMarkers = true }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (env) (count_over_time({source=\"dedicated\", host=~\"$host\", env=~\"$env\"} |~ \"(?i)(error|exception|failed|failure|fatal|panic|timeout|stacktrace)\"[$__range]))"
            legendFormat = "{{env}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 4
        title       = "Nginx 5xx"
        type        = "stat"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 5, w = 6, x = 18, y = 0 }
        fieldConfig = { defaults = { unit = "short", thresholds = { mode = "absolute", steps = [{ color = "green", value = null }, { color = "yellow", value = 1 }, { color = "red", value = 5 }] } }, overrides = [] }
        options     = { colorMode = "background", graphMode = "area", justifyMode = "auto", orientation = "auto", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, textMode = "auto" }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (env) (count_over_time({source=\"dedicated\", host=~\"$host\", env=~\"$env\", service=\"nginx\"} |~ \"^5[0-9][0-9]\"[$__range]))"
            legendFormat = "{{env}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 5
        title       = "Error Timeline"
        type        = "state-timeline"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 7, w = 24, x = 0, y = 5 }
        fieldConfig = { defaults = { unit = "short", thresholds = { mode = "absolute", steps = [{ color = "green", value = null }, { color = "yellow", value = 1 }, { color = "red", value = 5 }] } }, overrides = [] }
        options     = { alignValue = "left", legend = { displayMode = "list", placement = "bottom", showLegend = true }, mergeValues = true, rowHeight = 0.8, showValue = "auto", tooltip = { mode = "single", sort = "none" } }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (env, service) (count_over_time({source=\"dedicated\", host=~\"$host\", env=~\"$env\"} |~ \"(?i)(error|exception|failed|failure|fatal|panic|timeout|stacktrace)\"[5m]))"
            legendFormat = "{{env}} / {{service}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 6
        title       = "Log Volume"
        type        = "timeseries"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 8, w = 12, x = 0, y = 12 }
        fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (env, service) (count_over_time({source=\"dedicated\", host=~\"$host\", env=~\"$env\"}[5m]))"
            legendFormat = "{{env}} / {{service}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 7
        title       = "Error Rate"
        type        = "timeseries"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 8, w = 12, x = 12, y = 12 }
        fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (env, service) (count_over_time({source=\"dedicated\", host=~\"$host\", env=~\"$env\"} |~ \"(?i)(error|exception|failed|failure|fatal|panic|timeout|stacktrace)\"[5m]))"
            legendFormat = "{{env}} / {{service}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 8
        title       = "Noisiest Services"
        type        = "bargauge"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 7, w = 8, x = 0, y = 20 }
        fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        options     = { displayMode = "gradient", minVizHeight = 10, minVizWidth = 0, namePlacement = "auto", orientation = "horizontal", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, showUnfilled = true, sizing = "auto", valueMode = "color" }
        targets = [
          {
            refId        = "A"
            expr         = "topk(12, sum by (env, service) (count_over_time({source=\"dedicated\", host=~\"$host\", env=~\"$env\"}[$__range])))"
            legendFormat = "{{env}} / {{service}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 9
        title       = "HTTP Status Mix"
        type        = "bargauge"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 7, w = 8, x = 8, y = 20 }
        fieldConfig = { defaults = { unit = "short" }, overrides = [] }
        options     = { displayMode = "lcd", minVizHeight = 10, minVizWidth = 0, namePlacement = "auto", orientation = "horizontal", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, showUnfilled = true, sizing = "auto", valueMode = "color" }
        targets = [
          {
            refId      = "A"
            expr       = "sum by (status) (count_over_time({source=\"dedicated\", host=~\"$host\", env=~\"$env\", service=\"nginx\"} | regexp `^(?P<status>[0-9]{3})` [$__range]))"
            queryType  = "range"
            datasource = local.loki_dashboard_ds
          }
        ]
      },
      {
        id          = 10
        title       = "Tomcat Stacktrace Bursts"
        type        = "bargauge"
        datasource  = local.loki_dashboard_ds
        gridPos     = { h = 7, w = 8, x = 16, y = 20 }
        fieldConfig = { defaults = { unit = "short", thresholds = { mode = "absolute", steps = [{ color = "green", value = null }, { color = "yellow", value = 1 }, { color = "red", value = 5 }] } }, overrides = [] }
        options     = { displayMode = "gradient", minVizHeight = 10, minVizWidth = 0, namePlacement = "auto", orientation = "horizontal", reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }, showUnfilled = true, sizing = "auto", valueMode = "color" }
        targets = [
          {
            refId        = "A"
            expr         = "sum by (env) (count_over_time({source=\"dedicated\", host=~\"$host\", env=~\"$env\", service=\"tomcat\"} |~ \"(?i)(exception|caused by|stacktrace|nosuchmethoderror|outofmemory|fatal)\"[$__range]))"
            legendFormat = "{{env}}"
            queryType    = "range"
            datasource   = local.loki_dashboard_ds
          }
        ]
      },
      {
        id         = 11
        title      = "Recent Stand Errors"
        type       = "logs"
        datasource = local.loki_dashboard_ds
        gridPos    = { h = 10, w = 12, x = 0, y = 27 }
        options    = { dedupStrategy = "none", enableLogDetails = true, prettifyLogMessage = false, showCommonLabels = false, showLabels = true, showTime = true, sortOrder = "Descending", wrapLogMessage = true }
        targets = [
          {
            refId      = "A"
            expr       = "{source=\"dedicated\", host=~\"$host\", env=~\"$env\"} |~ \"(?i)(error|exception|failed|failure|fatal|panic|timeout|stacktrace|caused by)\""
            queryType  = "range"
            datasource = local.loki_dashboard_ds
          }
        ]
      },
      {
        id         = 12
        title      = "Live Stand Logs"
        type       = "logs"
        datasource = local.loki_dashboard_ds
        gridPos    = { h = 10, w = 12, x = 12, y = 27 }
        options    = { dedupStrategy = "none", enableLogDetails = true, prettifyLogMessage = false, showCommonLabels = false, showLabels = true, showTime = true, sortOrder = "Descending", wrapLogMessage = true }
        targets = [
          {
            refId      = "A"
            expr       = "{source=\"dedicated\", host=~\"$host\", env=~\"$env\"}"
            queryType  = "range"
            datasource = local.loki_dashboard_ds
          }
        ]
      }
    ]
  }
}

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "7.0.0"
  timeout    = 900

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"

      loki = {
        auth_enabled = false

        commonConfig = {
          replication_factor = 1
        }

        schemaConfig = {
          configs = [
            {
              from         = "2024-04-01"
              store        = "tsdb"
              object_store = "s3"
              schema       = "v13"
              index = {
                prefix = "loki_index_"
                period = "24h"
              }
            }
          ]
        }

        storage = {
          type = "s3"
          bucketNames = {
            chunks = var.s3_bucket
            ruler  = var.s3_bucket
            admin  = var.s3_bucket
          }
          s3 = {
            endpoint         = var.s3_endpoint_url
            region           = var.s3_region
            accessKeyId      = var.s3_access_key
            secretAccessKey  = var.s3_secret_key
            s3ForcePathStyle = true
            insecure         = false
            signatureVersion = "v4"
          }
        }

        limits_config = {
          retention_period = "168h"
        }

        compactor = {
          retention_enabled    = true
          delete_request_store = "s3"
        }
      }

      singleBinary = {
        replicas = 1
        persistence = {
          enabled      = true
          size         = "10Gi"
          storageClass = "fast.ru-7a"
        }
        resources = {
          requests = {
            cpu    = "10m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }
      }

      read = {
        replicas = 0
      }
      write = {
        replicas = 0
      }
      backend = {
        replicas = 0
      }

      chunksCache = {
        enabled = false
      }
      resultsCache = {
        enabled = false
      }
      gateway = {
        enabled = false
      }
      lokiCanary = {
        enabled = false
      }
      test = {
        enabled = false
      }
      minio = {
        enabled = false
      }
    })
  ]
}

resource "helm_release" "grafana" {
  name       = "grafana"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "10.5.15"
  timeout    = 600

  values = [
    yamlencode({
      adminUser     = "admin"
      adminPassword = random_password.grafana_admin.result

      "grafana.ini" = var.grafana_public_url == null ? {} : {
        server = {
          root_url            = var.grafana_public_url
          serve_from_sub_path = var.grafana_public_sub_path != null
        }
      }

      deploymentStrategy = {
        type = "Recreate"
      }

      persistence = {
        enabled          = true
        size             = "2Gi"
        storageClassName = "fast.ru-7a"
      }

      resources = {
        requests = {
          cpu    = "10m"
          memory = "192Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }

      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              name      = "Loki"
              type      = "loki"
              access    = "proxy"
              url       = local.loki_url
              isDefault = true
            }
          ]
        }
      }

      dashboardProviders = {
        "dashboardproviders.yaml" = {
          apiVersion = 1
          providers = [
            {
              name            = "default"
              orgId           = 1
              folder          = ""
              type            = "file"
              disableDeletion = false
              editable        = true
              options = {
                path = "/var/lib/grafana/dashboards/default"
              }
            }
          ]
        }
      }

      dashboards = {
        default = {
          aof-environments = {
            json = jsonencode(local.aof_environments_dashboard)
          }
          dedicated-stands = {
            json = jsonencode(local.dedicated_stands_dashboard)
          }
        }
      }

      testFramework = {
        enabled = false
      }
    })
  ]

  depends_on = [
    helm_release.loki
  ]
}

resource "helm_release" "alloy" {
  name       = "alloy"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = "1.10.0"
  timeout    = 600

  values = [
    yamlencode({
      controller = {
        type = "daemonset"
      }

      configReloader = {
        resources = {
          requests = {
            cpu    = "1m"
            memory = "32Mi"
          }
        }
      }

      alloy = {
        mounts = {
          varlog           = true
          dockercontainers = false
        }

        resources = {
          requests = {
            cpu    = "1m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }

        configMap = {
          create  = true
          content = <<-EOT
            discovery.kubernetes "pods" {
              role = "pod"
            }

            discovery.relabel "pod_logs" {
              targets = discovery.kubernetes.pods.targets

              rule {
                source_labels = ["__meta_kubernetes_namespace"]
                regex         = "${local.namespace_keep_regex}"
                action        = "keep"
              }

              rule {
                source_labels = ["__meta_kubernetes_pod_node_name"]
                regex         = env("K8S_NODE_NAME")
                action        = "keep"
              }

              rule {
                source_labels = ["__meta_kubernetes_namespace"]
                target_label  = "namespace"
              }

              rule {
                source_labels = ["__meta_kubernetes_pod_name"]
                target_label  = "pod"
              }

              rule {
                source_labels = ["__meta_kubernetes_pod_container_name"]
                target_label  = "container"
              }

              rule {
                source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
                target_label  = "app"
              }

              rule {
                source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_instance"]
                target_label  = "instance"
              }

              rule {
                source_labels = [
                  "__meta_kubernetes_namespace",
                  "__meta_kubernetes_pod_name",
                  "__meta_kubernetes_pod_uid",
                  "__meta_kubernetes_pod_container_name",
                ]
                separator    = "/"
                regex        = "([^/]+)/([^/]+)/([^/]+)/([^/]+)"
                target_label = "__path__"
                replacement  = "/var/log/pods/$${1}_$${2}_$${3}/$${4}/*.log"
              }
            }

            loki.source.file "pod_logs" {
              targets    = local.file_match.pod_logs.targets
              forward_to = [loki.write.default.receiver]
            }

            local.file_match "pod_logs" {
              path_targets = discovery.relabel.pod_logs.output
            }

            loki.write "default" {
              endpoint {
                url = "${local.loki_url}/loki/api/v1/push"
              }
            }
          EOT
        }
      }
    })
  ]

  depends_on = [
    helm_release.loki
  ]
}

resource "helm_release" "alloy_gateway" {
  name       = "alloy-gateway"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = "1.10.0"
  timeout    = 600

  values = [
    yamlencode({
      controller = {
        type     = "deployment"
        replicas = 1
      }

      rbac = {
        create = false
      }

      serviceAccount = {
        create                       = true
        automountServiceAccountToken = false
      }

      service = {
        enabled = true
        type    = "ClusterIP"
      }

      configReloader = {
        resources = {
          requests = {
            cpu    = "1m"
            memory = "32Mi"
          }
        }
      }

      alloy = {
        resources = {
          requests = {
            cpu    = "1m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }

        extraPorts = [
          {
            name       = "loki-push"
            port       = 9999
            targetPort = 9999
            protocol   = "TCP"
          }
        ]

        configMap = {
          create  = true
          content = <<-EOT
            loki.source.api "dedicated" {
              http {
                listen_address = "0.0.0.0"
                listen_port    = 9999
              }

              labels = {
                source = "dedicated",
              }

              forward_to = [loki.write.default.receiver]
            }

            loki.write "default" {
              endpoint {
                url = "${local.loki_url}/loki/api/v1/push"
              }
            }
          EOT
        }
      }
    })
  ]

  depends_on = [
    helm_release.loki
  ]
}
