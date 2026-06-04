locals {
  frontend_s3_secret_name = "aof-frontend-s3"
  registry_secret_name    = "aof-registry-push"
  frontend_bucket_map_entries = join(", ", [
    for instance, bucket in var.frontend_s3_buckets : "'${instance}': '${bucket}'"
  ])
  frontend_default_git_branches = {
    dev     = "develop"
    feature = "develop"
    release = "release"
  }
  backend_default_git_branches = {
    dev     = "feat/containerization"
    feature = "feat/containerization"
    release = "feat/containerization"
  }
  frontend_git_branch_map_entries = join(", ", [
    for instance, branch in local.frontend_default_git_branches : "'${instance}': '${branch}'"
  ])
  backend_git_branch_map_entries = join(", ", [
    for instance, branch in local.backend_default_git_branches : "'${instance}': '${branch}'"
  ])

  frontend_job_script = <<-EOT
    pipelineJob('${var.frontend_job_name}') {
      description('${var.frontend_job_description}')
      keepDependencies(false)
      parameters {
        choiceParam('INSTANCE', ${jsonencode(var.frontend_instances)}, 'Frontend instance and S3 bucket to deploy.')
        stringParam('GIT_BRANCH', '', 'Optional Git branch override. Empty uses the default branch for the selected instance.')
        stringParam('GIT_CREDENTIALS_ID', 'github-aof-token', 'Jenkins credential ID for private Git repositories.')
        stringParam('BUILD_COMMAND', 'npm run build', 'Frontend build command.')
      }
      definition {
        cps {
          sandbox(true)
          script('''
            def frontRepo = 'https://github.com/akuzmin90/aof-front.git'
            def frontendBuckets = [${local.frontend_bucket_map_entries}]
            def defaultGitBranches = [${local.frontend_git_branch_map_entries}]

            podTemplate(yaml: """
            apiVersion: v1
            kind: Pod
            spec:
              containers:
                - name: jnlp
                  image: jenkins/inbound-agent:latest-jdk21
                - name: node
                  image: node:18-bookworm
                  command:
                    - cat
                  tty: true
                  env:
                    - name: NODE_OPTIONS
                      value: --max-old-space-size=3072
                  resources:
                    requests:
                      cpu: 100m
                      memory: 3Gi
                    limits:
                      cpu: "2"
                      memory: 4Gi
                - name: mc
                  image: quay.io/minio/mc:latest
                  command:
                    - cat
                  tty: true
                  env:
                    - name: S3_ENDPOINT
                      value: ${var.frontend_s3_endpoint_url}
                    - name: S3_ACCESS_KEY
                      valueFrom:
                        secretKeyRef:
                          name: ${local.frontend_s3_secret_name}
                          key: access-key
                    - name: S3_SECRET_KEY
                      valueFrom:
                        secretKeyRef:
                          name: ${local.frontend_s3_secret_name}
                          key: secret-key
            """) {
              node(POD_LABEL) {
                def bucket = frontendBuckets[params.INSTANCE]
                def gitBranch = params.GIT_BRANCH?.trim()
                if (!gitBranch) {
                  gitBranch = defaultGitBranches[params.INSTANCE] ?: params.INSTANCE
                }

                if (!bucket) {
                  error("No frontend S3 bucket configured for INSTANCE=" + params.INSTANCE)
                }

                stage('Checkout') {
                  def checkoutConfig = [branch: gitBranch, url: frontRepo]

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
                    withEnv(['S3_BUCKET=' + bucket]) {
                      sh 'set -eu; mc alias set target "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY"; mc mb --ignore-existing "target/$S3_BUCKET"; mc mirror --overwrite --remove --attr "x-amz-acl=public-read" dist "target/$S3_BUCKET"; mc anonymous set download "target/$S3_BUCKET" || true; echo "Uploaded frontend to s3://$S3_BUCKET/"'
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
    pipelineJob('${var.backend_job_name}') {
      description('Builds aof-back from the selected branch, pushes the image, and deploys the same instance with Helm.')
      keepDependencies(false)
      parameters {
        choiceParam('INSTANCE', ${jsonencode(var.frontend_instances)}, 'Backend instance and Kubernetes namespace to deploy.')
        stringParam('GIT_BRANCH', '', 'Optional Git branch override. Empty uses the default branch for the selected instance.')
        stringParam('GIT_CREDENTIALS_ID', 'github-aof-token', 'Jenkins credential ID for private Git repositories.')
        stringParam('IMAGE_TAG', '', 'Optional image tag. Empty means BRANCH-build_number.')
      }
      definition {
        cps {
          sandbox(true)
          script('''
            def backRepo = 'https://github.com/akuzmin90/aof-back.git'
            def defaultGitBranches = [${local.backend_git_branch_map_entries}]

            podTemplate(serviceAccount: 'jenkins', yaml: """
            apiVersion: v1
            kind: Pod
            spec:
              containers:
                - name: jnlp
                  image: jenkins/inbound-agent:latest-jdk21
                - name: kaniko
                  image: gcr.io/kaniko-project/executor:v1.23.2-debug
                  command:
                    - cat
                  tty: true
                  env:
                    - name: REGISTRY_SERVER
                      valueFrom:
                        secretKeyRef:
                          name: ${local.registry_secret_name}
                          key: server
                    - name: REGISTRY_USERNAME
                      valueFrom:
                        secretKeyRef:
                          name: ${local.registry_secret_name}
                          key: username
                    - name: REGISTRY_PASSWORD
                      valueFrom:
                        secretKeyRef:
                          name: ${local.registry_secret_name}
                          key: password
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
                def imageTag = params.IMAGE_TAG?.trim()
                if (!imageTag) {
                  imageTag = "$${params.INSTANCE}-$${env.BUILD_NUMBER}".replaceAll('[^A-Za-z0-9_.-]', '-')
                }

                def gitBranch = params.GIT_BRANCH?.trim()
                if (!gitBranch) {
                  gitBranch = defaultGitBranches[params.INSTANCE] ?: params.INSTANCE
                }

                def namespace = "aof-$${params.INSTANCE}"
                def host = "$${params.INSTANCE}.${var.app_domain_suffix}"
                def dbCluster = "aof-$${params.INSTANCE}-db"

                currentBuild.displayName = "#$${env.BUILD_NUMBER} $${params.INSTANCE} $${gitBranch} $${imageTag}"

                stage('Checkout') {
                  def checkoutConfig = [branch: gitBranch, url: backRepo]

                  if (params.GIT_CREDENTIALS_ID?.trim()) {
                    checkoutConfig.credentialsId = params.GIT_CREDENTIALS_ID.trim()
                  }

                  git checkoutConfig
                }

                stage('Build and Push Image') {
                  container('kaniko') {
                    withEnv([
                      "IMAGE_REPOSITORY=${var.backend_image_repository}",
                      "IMAGE_TAG=$${imageTag}"
                    ]) {
                      sh 'set -eu; AUTH=$(printf "%s:%s" "$REGISTRY_USERNAME" "$REGISTRY_PASSWORD" | base64 | tr -d "\\n"); printf "%s\\n" "{" "  \\"auths\\": {" "    \\"$REGISTRY_SERVER\\": {" "      \\"auth\\": \\"$AUTH\\"" "    }" "  }" "}" > /kaniko/.docker/config.json'
                      sh 'set -eu; /kaniko/executor --context "$WORKSPACE" --dockerfile "$WORKSPACE/Dockerfile" --destination "$IMAGE_REPOSITORY:$IMAGE_TAG" --cache=true'
                    }
                  }
                }

                stage('Deploy') {
                  container('helm') {
                    withEnv([
                      "IMAGE_REPOSITORY=${var.backend_image_repository}",
                      "IMAGE_TAG=$${imageTag}",
                      "NAMESPACE=$${namespace}",
                      "HOST=$${host}",
                      "DB_CLUSTER=$${dbCluster}",
                      "TLS_SECRET=$${params.INSTANCE}-k8s-zazer-fun-tls"
                    ]) {
                      sh([
                        'set -eu',
                        'kubectl get namespace "$NAMESPACE" >/dev/null',
                        'DB_SECRET="$DB_CLUSTER-app"',
                        'DB_USERNAME=$(kubectl -n "$NAMESPACE" get secret "$DB_SECRET" -o jsonpath="{.data.username}" | base64 -d)',
                        'DB_PASSWORD=$(kubectl -n "$NAMESPACE" get secret "$DB_SECRET" -o jsonpath="{.data.password}" | base64 -d)',
                        'CLIENT_ID=$(kubectl -n "$NAMESPACE" get secret aof-back-client-id -o jsonpath="{.data.secret}" 2>/dev/null | base64 -d || true)',
                        'if [ -z "$CLIENT_ID" ]; then',
                        '  CLIENT_ID=$(date +%s%N | sha256sum | cut -c1-32)',
                        '  kubectl -n "$NAMESPACE" create secret generic aof-back-client-id --from-literal=secret="$CLIENT_ID"',
                        'fi',
                        'cat > /tmp/aof-back-values.yaml <<EOF',
                        'fullnameOverride: aof-back',
                        'image:',
                        '  repository: $IMAGE_REPOSITORY',
                        '  tag: $IMAGE_TAG',
                        '  pullPolicy: IfNotPresent',
                        'imagePullSecrets:',
                        '  - name: selectel-registry',
                        'database:',
                        '  url: jdbc:postgresql://$DB_CLUSTER-rw.$NAMESPACE.svc.cluster.local:5432/aof',
                        '  username: $DB_USERNAME',
                        '  password: "$DB_PASSWORD"',
                        'clientId:',
                        '  existingSecret: aof-back-client-id',
                        '  secretKey: secret',
                        'redis:',
                        '  host: redis.$NAMESPACE.svc.cluster.local',
                        '  port: "6379"',
                        '  password: ""',
                        'ignite:',
                        '  addresses: ignite.$NAMESPACE.svc.cluster.local:47500',
                        'rabbitmq:',
                        '  host: rabbitmq.$NAMESPACE.svc.cluster.local',
                        '  stompPort: 61613',
                        '  existingSecret: rabbitmq-credentials',
                        '  usernameKey: username',
                        '  passwordKey: password',
                        'ingress:',
                        '  enabled: true',
                        '  className: nginx',
                        '  annotations:',
                        '    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"',
                        '    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"',
                        '    nginx.ingress.kubernetes.io/ssl-redirect: "true"',
                        '  hosts:',
                        '    - host: $HOST',
                        '      paths:',
                        '        - path: /api',
                        '          pathType: Prefix',
                        '  tls:',
                        '    - secretName: $TLS_SECRET',
                        '      hosts:',
                        '        - $HOST',
                        'EOF',
                        'helm upgrade --install aof-back chart --namespace "$NAMESPACE" -f /tmp/aof-back-values.yaml --wait --timeout 10m'
                      ].join('\n'))
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

  database_dump_job_script = <<-EOT
    pipelineJob('aof-db-dump') {
      description('Creates a manual PostgreSQL dump for the selected AOF instance and uploads it to S3.')
      keepDependencies(false)
      parameters {
        choiceParam('INSTANCE', ${jsonencode(var.frontend_instances)}, 'Deployment instance and namespace suffix.')
        stringParam('DATABASE', 'aof', 'Database to dump.')
        stringParam('DUMP_NAME', '', 'Optional dump name prefix. Empty uses only database and UTC date/time.')
      }
      definition {
        cps {
          sandbox(true)
          script('''
            podTemplate(yaml: """
            apiVersion: v1
            kind: Pod
            spec:
              containers:
                - name: jnlp
                  image: jenkins/inbound-agent:latest-jdk21
                - name: postgres
                  image: postgres:16-alpine
                  command:
                    - cat
                  tty: true
                - name: kubectl
                  image: dtzar/helm-kubectl:3.16.4
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
                def namespace = "aof-$${params.INSTANCE}"
                def clusterName = "aof-$${params.INSTANCE}-db"
                def dumpPath = "$${params.INSTANCE}/manual"

                stage('Prepare Secrets') {
                  container('kubectl') {
                    withEnv([
                      "NAMESPACE=$${namespace}",
                      "DB_SECRET=$${clusterName}-app"
                    ]) {
                      sh 'set -eu; kubectl -n "$NAMESPACE" get secret "$DB_SECRET" -o jsonpath="{.data.username}" | base64 -d > .db-user; kubectl -n "$NAMESPACE" get secret "$DB_SECRET" -o jsonpath="{.data.password}" | base64 -d > .db-password; kubectl -n "$NAMESPACE" get secret aof-postgres-s3 -o jsonpath="{.data.ACCESS_KEY_ID}" | base64 -d > .s3-access-key; kubectl -n "$NAMESPACE" get secret aof-postgres-s3 -o jsonpath="{.data.ACCESS_SECRET_KEY}" | base64 -d > .s3-secret-key'
                    }
                  }
                }

                stage('Dump') {
                  container('postgres') {
                    withEnv([
                      "PGHOST=$${clusterName}-rw.$${namespace}.svc.cluster.local",
                      "PGPORT=5432",
                      "DATABASE=$${params.DATABASE}",
                      "DUMP_NAME=$${params.DUMP_NAME}"
                    ]) {
                      sh 'set -e; export PGUSER=$(cat .db-user); export PGPASSWORD=$(cat .db-password); DATE=$(date -u +%Y%m%dT%H%M%SZ); DUMP_NAME="$${DUMP_NAME:-}"; if [ -n "$DUMP_NAME" ]; then SAFE_NAME=$(printf "%s" "$DUMP_NAME" | tr -c "A-Za-z0-9._-" "-"); DUMP_FILE="$SAFE_NAME-$DATE.dump"; else DUMP_FILE="$DATABASE-$DATE.dump"; fi; pg_dump -Fc -d "$DATABASE" -f "$DUMP_FILE"; printf "%s" "$DUMP_FILE" > dump-name.txt; ls -lh "$DUMP_FILE"'
                    }
                  }
                }

                stage('Upload') {
                  container('mc') {
                    withEnv([
                      "NAMESPACE=$${namespace}",
                      "S3_ENDPOINT=${var.postgres_s3_endpoint_url}",
                      "DUMP_BUCKET=${var.postgres_dump_bucket}",
                      "DUMP_PATH=$${dumpPath}"
                    ]) {
                      sh 'set -eu; export S3_ACCESS_KEY=$(cat .s3-access-key); export S3_SECRET_KEY=$(cat .s3-secret-key); DUMP_FILE=$(cat dump-name.txt); mc alias set target "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY"; mc mb --ignore-existing "target/$DUMP_BUCKET"; mc cp "$DUMP_FILE" "target/$DUMP_BUCKET/$DUMP_PATH/$DUMP_FILE"; echo "Uploaded: s3://$DUMP_BUCKET/$DUMP_PATH/$DUMP_FILE"'
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

  database_restore_job_script = <<-EOT
    pipelineJob('aof-db-restore') {
      description('Restores a PostgreSQL dump from S3 into the selected AOF instance database.')
      keepDependencies(false)
      parameters {
        choiceParam('INSTANCE', ${jsonencode(var.frontend_instances)}, 'Deployment instance and namespace suffix.')
        stringParam('DUMP_OBJECT', '', 'Object key inside ${var.postgres_dump_bucket}, for example feature/manual/aof-manual-20260525T120000Z.dump.')
        stringParam('TARGET_DATABASE', 'aof', 'Database to restore into.')
        booleanParam('RESET_SCHEMA', true, 'Drop and recreate public schema before restoring.')
      }
      definition {
        cps {
          sandbox(true)
          script('''
            podTemplate(yaml: """
            apiVersion: v1
            kind: Pod
            spec:
              containers:
                - name: jnlp
                  image: jenkins/inbound-agent:latest-jdk21
                - name: postgres
                  image: postgres:16-alpine
                  command:
                    - cat
                  tty: true
                - name: kubectl
                  image: dtzar/helm-kubectl:3.16.4
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
                def namespace = "aof-$${params.INSTANCE}"
                def clusterName = "aof-$${params.INSTANCE}-db"

                stage('Prepare Secrets') {
                  container('kubectl') {
                    withEnv([
                      "NAMESPACE=$${namespace}",
                      "DB_SECRET=$${clusterName}-app"
                    ]) {
                      sh 'set -eu; kubectl -n "$NAMESPACE" get secret "$DB_SECRET" -o jsonpath="{.data.username}" | base64 -d > .db-user; kubectl -n "$NAMESPACE" get secret "$DB_SECRET" -o jsonpath="{.data.password}" | base64 -d > .db-password; kubectl -n "$NAMESPACE" get secret aof-postgres-s3 -o jsonpath="{.data.ACCESS_KEY_ID}" | base64 -d > .s3-access-key; kubectl -n "$NAMESPACE" get secret aof-postgres-s3 -o jsonpath="{.data.ACCESS_SECRET_KEY}" | base64 -d > .s3-secret-key'
                    }
                  }
                }

                stage('Download') {
                  container('mc') {
                    withEnv([
                      "S3_ENDPOINT=${var.postgres_s3_endpoint_url}",
                      "DUMP_BUCKET=${var.postgres_dump_bucket}",
                      "DUMP_OBJECT=$${params.DUMP_OBJECT}"
                    ]) {
                      sh 'set -eu; test -n "$DUMP_OBJECT"; export S3_ACCESS_KEY=$(cat .s3-access-key); export S3_SECRET_KEY=$(cat .s3-secret-key); mc alias set target "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY"; mc cp "target/$DUMP_BUCKET/$DUMP_OBJECT" restore.dump; ls -lh restore.dump'
                    }
                  }
                }

                stage('Restore') {
                  container('postgres') {
                    withEnv([
                      "PGHOST=$${clusterName}-rw.$${namespace}.svc.cluster.local",
                      "PGPORT=5432",
                      "TARGET_DATABASE=$${params.TARGET_DATABASE}",
                      "RESET_SCHEMA=$${params.RESET_SCHEMA}"
                    ]) {
                      sh 'set -eu; export PGUSER=$(cat .db-user); export PGPASSWORD=$(cat .db-password); if [ "$RESET_SCHEMA" = "true" ]; then psql -d "$TARGET_DATABASE" -v ON_ERROR_STOP=1 -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public AUTHORIZATION \\"$PGUSER\\";"; fi; pg_restore --no-owner --no-acl --clean --if-exists -d "$TARGET_DATABASE" restore.dump'
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

  stale_job_names = [
    "aof-front-local-s3",
    "aof-back-local-k8s",
    "aof-front-selectel-s3",
    "aof-back-selectel-k8s",
    "aof-db-dump-selectel-s3",
    "aof-db-restore-selectel-s3",
    "aof-db-dump-manual",
    "aof-db-restore-dev",
    "aof-db-dev-dump-manual",
    "aof-db-dev-restore-dev",
    "aof-db-feature-dump-manual",
    "aof-db-feature-restore-dev",
    "aof-db-release-dump-manual",
    "aof-db-release-restore-dev"
  ]

  job_scripts = concat([
    local.frontend_job_script,
    local.backend_job_script,
    local.database_dump_job_script,
    local.database_restore_job_script
  ], var.extra_job_scripts)
}

resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = "jenkins"
  }
}

resource "kubernetes_secret" "frontend_s3" {
  metadata {
    name      = local.frontend_s3_secret_name
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  type = "Opaque"

  data = {
    access-key = var.frontend_s3_access_key
    secret-key = var.frontend_s3_secret_key
  }
}

resource "kubernetes_secret" "registry_push" {
  metadata {
    name      = local.registry_secret_name
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  type = "Opaque"

  data = {
    server   = var.registry_server
    username = var.registry_username
    password = var.registry_password
  }
}

resource "helm_release" "jenkins" {
  name       = "jenkins"
  namespace  = kubernetes_namespace.jenkins.metadata[0].name
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = "5.9.22"
  timeout    = 900
  values = [
    yamlencode({
      controller = {
        initScripts = {
          "delete-stale-aof-jobs" = <<-SCRIPT
            import jenkins.model.Jenkins

            def jenkins = Jenkins.get()
            def staleJobs = ${jsonencode(local.stale_job_names)}

            staleJobs.each { jobName ->
              def item = jenkins.getItemByFullName(jobName)
              if (item != null) {
                println("Deleting stale Jenkins job: " + jobName)
                item.delete()
              }

              def jobDir = new File(jenkins.rootDir, "jobs/" + jobName)
              if (jobDir.exists()) {
                println("Deleting stale Jenkins job directory: " + jobDir.absolutePath)
                jobDir.deleteDir()
              }
            }
          SCRIPT

          "reset-admin-password" = <<-SCRIPT
            import hudson.security.HudsonPrivateSecurityRealm
            import hudson.security.HudsonPrivateSecurityRealm.Details
            import jenkins.model.Jenkins

            def jenkins = Jenkins.get()
            def username = new File('/run/secrets/additional/chart-admin-username').text.trim()
            def password = new File('/run/secrets/additional/chart-admin-password').text.trim()

            if (jenkins.getSecurityRealm() instanceof HudsonPrivateSecurityRealm) {
              def realm = (HudsonPrivateSecurityRealm) jenkins.getSecurityRealm()
              def user = realm.getUser(username)

              if (user == null) {
                realm.createAccount(username, password)
              } else {
                user.addProperty(Details.fromPlainPassword(password))
              }

              jenkins.save()
              println("Reset Jenkins admin password for user: " + username)
            } else {
              println("Skipped Jenkins admin password reset because security realm is not HudsonPrivateSecurityRealm")
            }
          SCRIPT
        }

        installPlugins = [
          "kubernetes:4384.v1b_6367f393d9",
          "workflow-aggregator:608.v67378e9d3db_1",
          "git:5.8.0",
          "configuration-as-code:latest",
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

  dynamic "set" {
    for_each = var.public_url != "" ? [var.public_url] : []

    content {
      name  = "controller.jenkinsUrl"
      value = set.value
    }
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
    name  = "persistence.storageClass"
    value = var.persistence_storage_class
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
