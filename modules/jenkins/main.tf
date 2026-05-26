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

  backend_job_script = <<-EOT
    pipelineJob('aof-back-local-k8s') {
      description('Builds aof-back image, pushes it to a registry, and deploys it to Kubernetes with Helm.')
      keepDependencies(false)
      parameters {
        stringParam('BRANCH', 'master', 'Git branch to deploy.')
        stringParam('GIT_CREDENTIALS_ID', '', 'Optional Jenkins credential ID for private Git repositories.')
        stringParam('REGISTRY_SERVER', '', 'Registry host, for example cr.selcloud.ru. Required for private registry auth.')
        stringParam('REGISTRY_CREDENTIALS_ID', '', 'Optional Jenkins username/password credentials for registry push.')
        stringParam('IMAGE_REPOSITORY', '', 'Full image repository, for example cr.selcloud.ru/aof-registry/aof-back.')
        stringParam('IMAGE_TAG', '', 'Optional image tag. Defaults to branch-build_number.')
        stringParam('RELEASE_NAME', 'aof-back', 'Helm release name.')
        stringParam('NAMESPACE', 'aof', 'Kubernetes namespace.')
        booleanParam('INGRESS_ENABLED', true, 'Expose backend under /api through ingress.')
      }
      definition {
        cps {
          sandbox(true)
          script('''
            def backRepo = 'https://github.com/akuzmin90/aof-back.git'

            podTemplate(serviceAccount: 'jenkins', yaml: """
            apiVersion: v1
            kind: Pod
            spec:
              containers:
                - name: kaniko
                  image: gcr.io/kaniko-project/executor:v1.23.2-debug
                  command:
                    - cat
                  tty: true
                  volumeMounts:
                    - name: kaniko-docker-config
                      mountPath: /kaniko/.docker
                - name: helm
                  image: dtzar/helm-kubectl:3.16.4
                  command:
                    - cat
                  tty: true
              volumes:
                - name: kaniko-docker-config
                  emptyDir: {}
            """) {
              node(POD_LABEL) {
                def imageTag = ''
                def imageRepository = ''

                stage('Checkout') {
                  def checkoutConfig = [branch: params.BRANCH, url: backRepo]

                  if (params.GIT_CREDENTIALS_ID?.trim()) {
                    checkoutConfig.credentialsId = params.GIT_CREDENTIALS_ID.trim()
                  }

                  git checkoutConfig
                }

                stage('Prepare') {
                  imageTag = params.IMAGE_TAG?.trim()
                  if (!imageTag) {
                    imageTag = "$${params.BRANCH}-$${env.BUILD_NUMBER}".replaceAll('[^A-Za-z0-9_.-]', '-')
                  }

                  imageRepository = params.IMAGE_REPOSITORY?.trim()
                  if (!imageRepository) {
                    error('IMAGE_REPOSITORY is required, for example cr.selcloud.ru/aof-registry/aof-back')
                  }

                  currentBuild.displayName = "#$${env.BUILD_NUMBER} $${imageTag}"
                }

                stage('Build and Push Image') {
                  container('kaniko') {
                    withEnv([
                      "IMAGE_REPOSITORY=$${imageRepository}",
                      "IMAGE_TAG=$${imageTag}",
                      "REGISTRY_SERVER=$${params.REGISTRY_SERVER?.trim() ?: ''}"
                    ]) {
                      if (params.REGISTRY_CREDENTIALS_ID?.trim()) {
                        withCredentials([usernamePassword(credentialsId: params.REGISTRY_CREDENTIALS_ID.trim(), usernameVariable: 'REGISTRY_USERNAME', passwordVariable: 'REGISTRY_PASSWORD')]) {
                          sh 'set -eu; AUTH=$(printf "%s:%s" "$REGISTRY_USERNAME" "$REGISTRY_PASSWORD" | base64 | tr -d "\\n"); printf "{\\"auths\\":{\\"%s\\":{\\"auth\\":\\"%s\\"}}}" "$REGISTRY_SERVER" "$AUTH" > /kaniko/.docker/config.json'
                        }
                      }

                      sh 'set -eu; /kaniko/executor --context "$WORKSPACE" --dockerfile "$WORKSPACE/Dockerfile" --destination "$IMAGE_REPOSITORY:$IMAGE_TAG" --cache=true'
                    }
                  }
                }

                stage('Deploy') {
                  container('helm') {
                    withEnv([
                      "IMAGE_REPOSITORY=$${imageRepository}",
                      "IMAGE_TAG=$${imageTag}",
                      "RELEASE_NAME=$${params.RELEASE_NAME}",
                      "NAMESPACE=$${params.NAMESPACE}",
                      "INGRESS_ENABLED=$${params.INGRESS_ENABLED}"
                    ]) {
                      sh 'set -eu; DB_PASSWORD=$(kubectl -n database get secret aof-db-app -o jsonpath="{.data.password}" | base64 -d); helm upgrade --install "$RELEASE_NAME" chart --namespace "$NAMESPACE" --create-namespace --set image.repository="$IMAGE_REPOSITORY" --set image.tag="$IMAGE_TAG" --set image.pullPolicy=IfNotPresent --set-string database.password="$DB_PASSWORD" --set ingress.enabled="$INGRESS_ENABLED" --wait --timeout 10m'
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

  job_scripts = concat([local.frontend_job_script, local.backend_job_script], var.extra_job_scripts)
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

resource "kubernetes_cluster_role" "jenkins_deployer" {
  metadata {
    name = "jenkins-aof-deployer"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "services", "secrets", "configmaps", "serviceaccounts", "pods", "events"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_cluster_role_binding" "jenkins_deployer" {
  metadata {
    name = "jenkins-aof-deployer"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.jenkins_deployer.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "jenkins"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }
}
