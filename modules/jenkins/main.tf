locals {
  frontend_job_script = <<-EOT
    pipelineJob('aof-front-local-s3') {
      description('Builds aof-front and uploads dist/ to the local MinIO S3-compatible bucket used by kind.')
      keepDependencies(false)
      parameters {
        stringParam('BRANCH', 'master', 'Git branch to deploy.')
        stringParam('GIT_CREDENTIALS_ID', '', 'Optional Jenkins credential ID for private Git repositories.')
        stringParam('BUILD_COMMAND', 'npm run build', 'Frontend build command.')
      }
      definition {
        cps {
          sandbox(true)
          script('''
            def frontRepo = 'https://github.com/akuzmin90/aof-front.git'

            podTemplate(yaml: """
            apiVersion: v1
            kind: Pod
            spec:
              containers:
                - name: node
                  image: node:18-bookworm
                  command:
                    - cat
                  tty: true
                - name: mc
                  image: quay.io/minio/mc:latest
                  command:
                    - cat
                  tty: true
            """) {
              node(POD_LABEL) {
                stage('Checkout') {
                  def checkoutConfig = [branch: params.BRANCH, url: frontRepo]

                  if (params.GIT_CREDENTIALS_ID?.trim()) {
                    checkoutConfig.credentialsId = params.GIT_CREDENTIALS_ID.trim()
                  }

                  git checkoutConfig
                }

                stage('Build') {
                  container('node') {
                    sh 'set -eu; npm install'
                    sh params.BUILD_COMMAND
                    sh 'set -eu; INDEX_FILE=$(find dist -maxdepth 1 -type f -name "index*.html" ! -name "index.html" | sort | tail -n 1); if [ -z "$INDEX_FILE" ]; then echo "No versioned index*.html found in dist"; exit 1; fi; cp "$INDEX_FILE" dist/index.html; echo "Created stable index.html from $(basename "$INDEX_FILE")"'
                  }
                }

                stage('Upload') {
                  container('mc') {
                    withEnv([
                      'MINIO_ENDPOINT=http://minio.minio.svc.cluster.local:9000',
                      'MINIO_BUCKET=aof-front',
                      'MINIO_ACCESS_KEY=minioadmin',
                      'MINIO_SECRET_KEY=minioadmin123'
                    ]) {
                      sh 'set -eu; mc alias set local "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"; mc mb --ignore-existing "local/$MINIO_BUCKET"; mc mirror --overwrite --remove dist "local/$MINIO_BUCKET"; mc anonymous set download "local/$MINIO_BUCKET"'
                    }
                  }
                }
              }
            }
          ''')
        }
      }
    }
  EOT

  job_scripts = concat([local.frontend_job_script], var.extra_job_scripts)
}

resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = "jenkins"
  }
}

resource "helm_release" "jenkins" {
  name       = "jenkins"
  namespace  = kubernetes_namespace.jenkins.metadata[0].name
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = "5.8.99"
  timeout    = 900
  values = [
    yamlencode({
      controller = {
        installPlugins = [
          "kubernetes:4384.v1b_6367f393d9",
          "workflow-aggregator:608.v67378e9d3db_1",
          "git:5.8.0",
          "configuration-as-code:2036.v0b_c2de701dcb_",
          "job-dsl:latest"
        ]

        JCasC = {
          configScripts = {
            "aof-jobs" = yamlencode({
              jobs = [
                for script in local.job_scripts : {
                  script = script
                }
              ]
            })
          }
        }
      }
    })
  ]

  lifecycle {
    precondition {
      condition     = var.admin_password != null && var.admin_password != ""
      error_message = "Set jenkins_admin_password before installing Jenkins."
    }
  }

  set {
    name  = "controller.serviceType"
    value = "ClusterIP"
  }

  set {
    name  = "controller.admin.username"
    value = "admin"
  }

  set_sensitive {
    name  = "controller.admin.password"
    value = var.admin_password
  }

  set {
    name  = "persistence.enabled"
    value = "true"
  }

  set {
    name  = "persistence.size"
    value = "20Gi"
  }

  set {
    name  = "controller.ingress.enabled"
    value = "false"
  }
}
