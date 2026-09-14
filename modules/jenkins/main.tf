locals {
  frontend_s3_secret_name = "aof-frontend-s3"
  registry_secret_name    = "aof-registry-push"
  backend_chart_name      = "aof-back-helm-chart"
  backend_chart_dir       = "${path.module}/charts/aof-back"
  backend_chart_files     = fileset(local.backend_chart_dir, "**")
  backend_chart_data = {
    for chart_file in local.backend_chart_files :
    replace(chart_file, "/", "__") => file("${local.backend_chart_dir}/${chart_file}")
  }
  backend_chart_volume_items = join("\n", [
    for chart_file in local.backend_chart_files :
    "                    - key: ${replace(chart_file, "/", "__")}\n                      path: ${chart_file}"
  ])
  frontend_bucket_map_entries = join(", ", [
    for instance, bucket in var.frontend_s3_buckets : "'${instance}': '${bucket}'"
  ])
  # Matches aof-back: the release stand is fed from `test`.
  # The aof-front `release` git branch is frozen (v266) and must not be the default.
  frontend_default_git_branches = {
    dev     = "develop"
    feature = "develop"
    release = "test"
  }
  backend_default_git_branches = {
    dev     = "develop"
    feature = "develop"
    release = "test"
  }
  backend_spring_profiles = {
    dev     = "tstDev"
    feature = "tstFea"
    release = "tstRel"
  }
  frontend_git_branch_map_entries = join(", ", [
    for instance, branch in local.frontend_default_git_branches : "'${instance}': '${branch}'"
  ])
  backend_git_branch_map_entries = join(", ", [
    for instance, branch in local.backend_default_git_branches : "'${instance}': '${branch}'"
  ])
  backend_spring_profile_map_entries = join(", ", [
    for instance, profile in local.backend_spring_profiles : "'${instance}': '${profile}'"
  ])

  frontend_jobs = concat([
    { name = var.frontend_job_name, instance = "", branch = "", poll = false }
    ], [for instance in ["dev", "feature", "release"] : {
      name     = "${var.frontend_job_name}-${instance}"
      instance = instance
      branch   = local.frontend_default_git_branches[instance]
      poll     = instance != "feature"
    } if contains(var.frontend_instances, instance)
  ])
  frontend_job_scripts = [for job in local.frontend_jobs : <<-EOT
    pipelineJob('${job.name}') {
      description('${var.frontend_job_description}')
      keepDependencies(false)
%{if job.instance != ""~}
      properties {
        disableConcurrentBuilds()
%{if job.poll~}
        pipelineTriggers {
          triggers {
            pollSCM {
              scmpoll_spec('H */3 * * *')
              ignorePostCommitHooks(true)
            }
          }
        }
%{endif~}
      }
%{endif~}
%{if job.instance == "" || job.instance == "feature"~}
      parameters {
%{if job.instance == ""~}
        choiceParam('INSTANCE', ${jsonencode(var.frontend_instances)}, 'Frontend instance and S3 bucket to deploy.')
        stringParam('GIT_BRANCH', '', 'Optional Git branch override. Empty uses the default branch for the selected instance.')
        stringParam('GIT_CREDENTIALS_ID', 'github-aof-token', 'Jenkins credential ID for private Git repositories.')
        stringParam('BUILD_COMMAND', 'npm run build', 'Frontend build command.')
%{else~}
        stringParam('GIT_BRANCH', '${job.branch}', 'Git branch to deploy to the feature stand.')
%{endif~}
      }
%{endif~}
      definition {
        cps {
          sandbox(true)
          script('''
            def instance = ${job.instance != "" ? "'${job.instance}'" : "params.INSTANCE"}
            def gitCredentialsId = ${job.instance != "" ? "'github-aof-token'" : "params.GIT_CREDENTIALS_ID?.trim()"}
            def frontRepo = 'https://github.com/akuzmin90/aof-front.git'
            def frontendBuckets = [${local.frontend_bucket_map_entries}]
            def defaultGitBranches = [${local.frontend_git_branch_map_entries}]

            lock(resource: 'aof-stand-' + instance, reason: 'Frontend deployment for ' + instance) {
              currentBuild.description = 'Waiting up to 15 minutes for autoscaled CI capacity'
              echo 'Requesting a dedicated CI node. Worker fallback is considered only if CI allocation fails for 15 minutes.'

              def ciAgentYaml = """
            apiVersion: v1
            kind: Pod
            spec:
              nodeSelector:
                workload: ci
              tolerations:
                - key: dedicated
                  operator: Equal
                  value: ci
                  effect: NoSchedule
              containers:
                - name: jnlp
                  image: jenkins/inbound-agent:latest-jdk21
                  resources:
                    requests:
                      cpu: 50m
                      memory: 128Mi
                    limits:
                      cpu: "500m"
                      memory: 512Mi
                - name: node
                  image: node:18-bookworm
                  command:
                    - cat
                  tty: true
                  env:
                    - name: NODE_OPTIONS
                      value: --max-old-space-size=4096
                  resources:
                    requests:
                      cpu: 250m
                      memory: 4Gi
                      ephemeral-storage: 4Gi
                    limits:
                      cpu: "1"
                      memory: 5Gi
                      ephemeral-storage: 12Gi
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
                  resources:
                    requests:
                      cpu: 10m
                      memory: 64Mi
                    limits:
                      cpu: "250m"
                      memory: 256Mi
            """
              def workerAgentYaml = """
            apiVersion: v1
            kind: Pod
            spec:
              nodeSelector:
                workload: compute
              initContainers:
                - name: worker-capacity-reservation
                  image: busybox:1.36.1
                  command:
                    - /bin/true
                  resources:
                    requests:
                      cpu: "1"
                      memory: 5Gi
                    limits:
                      cpu: "1"
                      memory: 5Gi
              containers:
                - name: jnlp
                  image: jenkins/inbound-agent:latest-jdk21
                  resources:
                    requests:
                      cpu: 50m
                      memory: 128Mi
                    limits:
                      cpu: "200m"
                      memory: 512Mi
                - name: node
                  image: node:18-bookworm
                  command:
                    - cat
                  tty: true
                  env:
                    - name: NODE_OPTIONS
                      value: --max-old-space-size=4096
                  resources:
                    requests:
                      cpu: 250m
                      memory: 4Gi
                      ephemeral-storage: 4Gi
                    limits:
                      cpu: "600m"
                      memory: 5Gi
                      ephemeral-storage: 12Gi
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
                  resources:
                    requests:
                      cpu: 10m
                      memory: 64Mi
                    limits:
                      cpu: "200m"
                      memory: 256Mi
            """
              if (!workerAgentYaml.contains('workload: compute') || !workerAgentYaml.contains('worker-capacity-reservation') || workerAgentYaml.contains('workload: ci')) {
                error('Internal error while rendering the compute fallback agent')
              }
              def agentLocation = 'CI'
              def executeFrontendBuild = {
                currentBuild.description = agentLocation + ' agent allocated'
                echo agentLocation + ' agent is ready; starting the build.'
                def bucket = frontendBuckets[instance]
                def gitBranch = ${job.poll ? "'${job.branch}'" : "params.GIT_BRANCH?.trim()"}
                if (!gitBranch) {
                  gitBranch = defaultGitBranches[instance] ?: instance
                }

                if (!bucket) {
                  error("No frontend S3 bucket configured for INSTANCE=" + instance)
                }

                stage('Checkout') {
                  def remoteConfig = [
                    url: frontRepo,
                    refspec: '+refs/heads/' + gitBranch + ':refs/remotes/origin/' + gitBranch
                  ]

                  if (gitCredentialsId) {
                    remoteConfig.credentialsId = gitCredentialsId
                  }

                  checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/' + gitBranch]],
                    extensions: [[$class: 'CloneOption', depth: 1, honorRefspec: true, noTags: true, shallow: true, timeout: 40]],
                    userRemoteConfigs: [remoteConfig]
                  ])
                }

                stage('Build') {
                  container('node') {
                    sh 'set -eu; if [ -f package-lock.json ]; then npm ci; else npm install; fi'
                    sh ${job.instance != "" ? "'npm run build'" : "params.BUILD_COMMAND"}
                    sh 'set -eu; INDEX_FILE=$(find dist -maxdepth 1 -type f -name "index*.html" ! -name "index.html" | sort | tail -n 1); if [ -z "$INDEX_FILE" ]; then echo "No versioned index*.html found in dist"; exit 1; fi; cp "$INDEX_FILE" dist/index.html; echo "Created stable index.html from $(basename "$INDEX_FILE")"'
                  }
                }

                stage('Upload') {
                  container('mc') {
                    withEnv(['S3_BUCKET=' + bucket]) {
                      sh 'set -eu; mc alias set target "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY"; mc mb --ignore-existing "target/$S3_BUCKET"; mc mirror --overwrite --exclude "index.html" --attr "x-amz-acl=public-read" dist "target/$S3_BUCKET"; mc cp --attr "x-amz-acl=public-read" dist/index.html "target/$S3_BUCKET/index.html"; mc anonymous set download "target/$S3_BUCKET" || true; echo "Uploaded frontend to s3://$S3_BUCKET/"'
                    }
                  }
                }
              }

              def ciAgentAllocated = false
              try {
                podTemplate(serviceAccount: 'jenkins', slaveConnectTimeout: 900, yaml: ciAgentYaml) {
                  node(POD_LABEL) {
                    ciAgentAllocated = true
                    executeFrontendBuild()
                  }
                }
              } catch (Exception ciAllocationFailure) {
                if (ciAgentAllocated) {
                  throw ciAllocationFailure
                }

                agentLocation = 'compute fallback'
                currentBuild.description = 'CI allocation failed; waiting for safe worker capacity'
                echo 'No CI agent connected within 15 minutes. Trying a compute worker with a 1 CPU / 5 GiB scheduling reservation.'
                podTemplate(serviceAccount: 'jenkins', slaveConnectTimeout: 600, yaml: workerAgentYaml) {
                  node(POD_LABEL) {
                    executeFrontendBuild()
                  }
                }
              }
            }
          ''')
        }
      }
    }
  EOT
  ]

  backend_tools_data = { for name in setunion(fileset("${path.module}/backend", "*.sh"), fileset("${path.module}/backend", "*.jq")) : name => file("${path.module}/backend/${name}") }
  backend_tools_name = "aof-back-ci-${substr(sha256(jsonencode(local.backend_tools_data)), 0, 12)}"
  backend_agent_yaml = { for pool in ["ci", "compute"] : pool => yamlencode({
    apiVersion = "v1"
    kind       = "Pod"
    spec = merge({
      nodeSelector = { workload = pool }
      containers = [
        {
          name  = "jnlp"
          image = "jenkins/inbound-agent:latest-jdk21"
          resources = {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { cpu = pool == "ci" ? "500m" : "200m", memory = "512Mi" }
          }
        },
        {
          name    = "kaniko"
          image   = "gcr.io/kaniko-project/executor:v1.23.2-debug"
          command = ["cat"]
          tty     = true
          env = [for entry in [{ name = "REGISTRY_SERVER", key = "server" }, { name = "REGISTRY_USERNAME", key = "username" }, { name = "REGISTRY_PASSWORD", key = "password" }] : {
            name      = entry.name
            valueFrom = { secretKeyRef = { name = local.registry_secret_name, key = entry.key } }
          }]
          volumeMounts = [{ name = "kaniko-docker-config", mountPath = "/kaniko/.docker" }, { name = "ci-tools", mountPath = "/ci-scripts", readOnly = true }]
          resources = {
            requests = { cpu = "250m", memory = "3Gi", ephemeral-storage = "4Gi" }
            limits   = { cpu = pool == "ci" ? "2" : "600m", memory = "4Gi", ephemeral-storage = "12Gi" }
          }
        },
        {
          name         = "helm"
          image        = "dtzar/helm-kubectl:3.16.4"
          command      = ["cat"]
          tty          = true
          volumeMounts = [{ name = "backend-chart", mountPath = "/charts/aof-back", readOnly = true }, { name = "ci-tools", mountPath = "/ci-scripts", readOnly = true }]
          resources = {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { cpu = pool == "ci" ? "500m" : "200m", memory = "512Mi" }
          }
        }
      ]
      volumes = [
        { name = "kaniko-docker-config", emptyDir = {} },
        { name = "ci-tools", configMap = { name = local.backend_tools_name } },
        { name = "backend-chart", configMap = { name = local.backend_chart_name, items = [for name in local.backend_chart_files : { key = replace(name, "/", "__"), path = name }] } }
      ]
      }, pool == "ci" ? {
      tolerations = [{ key = "dedicated", operator = "Equal", value = "ci", effect = "NoSchedule" }]
      } : {}, pool == "compute" ? {
      initContainers = [{ name = "worker-capacity-reservation", image = "busybox:1.36.1", command = ["/bin/true"], resources = { requests = { cpu = "1", memory = "5Gi" }, limits = { cpu = "1", memory = "5Gi" } } }]
    } : {})
  }) }

  # Each polling job needs its own checkout history and fixed branch. Keep the
  # parameterized job for manual deployments to any configured instance.
  backend_jobs = concat([
    {
      name      = var.backend_job_name
      instances = var.frontend_instances
      branch    = ""
      poll      = false
    }
    ], [
    for instance in ["dev", "feature", "release"] : {
      name      = "${var.backend_job_name}-${instance}"
      instances = [instance]
      branch    = local.backend_default_git_branches[instance]
      poll      = instance != "feature"
    } if contains(var.frontend_instances, instance)
  ])

  backend_job_scripts = [for job in local.backend_jobs : <<-EOT
    pipelineJob('${job.name}') {
      description('Builds aof-back from the selected branch, pushes the image, and deploys the same instance with Helm.')
      keepDependencies(false)
      logRotator { artifactDaysToKeep(14); artifactNumToKeep(20) }

%{if job.branch != ""~}
      properties {
        disableConcurrentBuilds()
        pipelineTriggers {
          triggers {
%{if job.poll~}
            pollSCM {
              scmpoll_spec('H */3 * * *')
              ignorePostCommitHooks(true)
            }
%{endif~}
          }
        }
      }
%{endif~}
      parameters {
%{if job.branch == ""~}
        choiceParam('INSTANCE', ${jsonencode(job.instances)}, 'Backend instance and Kubernetes namespace to deploy.')
        stringParam('GIT_BRANCH', '', 'Optional Git branch override. Empty uses the default branch for the selected instance.')
        stringParam('GIT_CREDENTIALS_ID', 'github-aof-token', 'Jenkins credential ID for private Git repositories.')
        stringParam('IMAGE_TAG', '', 'Optional image tag. Empty means INSTANCE-build_number-commit.')
%{endif~}
%{if job.branch != "" && job.instances[0] == "feature"~}
        stringParam('GIT_BRANCH', '${job.branch}', 'Git branch to deploy to the feature stand.')
%{endif~}
        stringParam('DEPLOY_TIMEOUT', '15m', 'Helm deployment timeout, for example 15m or 30m. Failed deployments retain pods for diagnostics; no automatic rollback.')
      }
      definition {
        cps {
          sandbox(true)
          script(new String('${base64encode(templatefile("${path.module}/backend/pipeline.groovy.tftpl", {
    instance_expression    = job.branch != "" ? "'${job.instances[0]}'" : "params.INSTANCE"
    branch_expression      = job.branch != "" && job.instances[0] != "feature" ? "'${job.branch}'" : "params.GIT_BRANCH?.trim()"
    credentials_expression = job.branch != "" ? "'github-aof-token'" : "params.GIT_CREDENTIALS_ID?.trim()"
    tag_expression         = job.branch != "" ? "''" : "params.IMAGE_TAG?.trim()"
    branch_entries         = local.backend_git_branch_map_entries
    profile_entries        = local.backend_spring_profile_map_entries
    ci_yaml                = local.backend_agent_yaml["ci"]
    worker_yaml            = local.backend_agent_yaml["compute"]
    image_repository       = var.backend_image_repository
    domain                 = var.app_domain_suffix
    legacy_domain          = var.legacy_app_domain_suffix
    admin_pvc              = var.backend_admin_pvc_name
}))}'.decodeBase64(), 'UTF-8'))
        }
      }
    }
  EOT
]

database_dump_job_script = <<-EOT
    pipelineJob('aof-db-dump') {
      description('Creates a manual PostgreSQL dump for the selected AOF instance and uploads it to S3.')
      keepDependencies(false)
      properties {
        disableConcurrentBuilds()
      }
      parameters {
        choiceParam('INSTANCE', ${jsonencode(var.frontend_instances)}, 'Deployment instance and namespace suffix.')
        stringParam('DATABASE', 'aof', 'Database to dump.')
        stringParam('DUMP_NAME', '', 'Optional dump name prefix. Empty uses only database and UTC date/time.')
      }
      definition {
        cps {
          sandbox(true)
          script('''
            currentBuild.description = 'Waiting for autoscaled CI capacity'
            echo 'CI capacity requested. If no CI node is ready, this build will remain queued while Kubernetes starts one.'

            podTemplate(serviceAccount: 'jenkins', slaveConnectTimeout: 3600, yaml: """
            apiVersion: v1
            kind: Pod
            spec:
              nodeSelector:
                workload: ci
              tolerations:
                - key: dedicated
                  operator: Equal
                  value: ci
                  effect: NoSchedule
              containers:
                - name: jnlp
                  image: jenkins/inbound-agent:latest-jdk21
                - name: postgres
                  image: postgres:11
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
                currentBuild.description = 'CI agent allocated'
                echo 'CI agent is ready; starting the build.'
                def namespace = 'aof-' + params.INSTANCE
                def clusterName = 'aof-' + params.INSTANCE + '-db'
                def dumpPath = params.INSTANCE + '/manual'

                stage('Prepare Secrets') {
                  container('kubectl') {
                    withEnv([
                      "NAMESPACE=" + namespace,
                      "DB_SECRET=" + clusterName + "-app"
                    ]) {
                      sh 'set -eu; kubectl -n "$NAMESPACE" get secret "$DB_SECRET" -o jsonpath="{.data.username}" | base64 -d > .db-user; kubectl -n "$NAMESPACE" get secret "$DB_SECRET" -o jsonpath="{.data.password}" | base64 -d > .db-password; kubectl -n "$NAMESPACE" get secret aof-postgres-s3 -o jsonpath="{.data.ACCESS_KEY_ID}" | base64 -d > .s3-access-key; kubectl -n "$NAMESPACE" get secret aof-postgres-s3 -o jsonpath="{.data.ACCESS_SECRET_KEY}" | base64 -d > .s3-secret-key'
                    }
                  }
                }

                stage('Dump') {
                  container('postgres') {
                    withEnv([
                      "PGHOST=" + clusterName + "-rw." + namespace + ".svc.cluster.local",
                      "PGPORT=5432",
                      "DATABASE=" + params.DATABASE,
                      "DUMP_NAME=" + params.DUMP_NAME
                    ]) {
                      sh 'set -e; export PGUSER=$(cat .db-user); export PGPASSWORD=$(cat .db-password); DATE=$(date -u +%Y%m%dT%H%M%SZ); if [ -n "$DUMP_NAME" ]; then SAFE_NAME=$(printf "%s" "$DUMP_NAME" | tr -c "A-Za-z0-9._-" "-"); DUMP_FILE="$SAFE_NAME-$DATE.dump"; else DUMP_FILE="$DATABASE-$DATE.dump"; fi; pg_dump -Fc -d "$DATABASE" -f "$DUMP_FILE"; printf "%s" "$DUMP_FILE" > dump-name.txt; ls -lh "$DUMP_FILE"'
                    }
                  }
                }

                stage('Upload') {
                  container('mc') {
                    withEnv([
                      "NAMESPACE=" + namespace,
                      "S3_ENDPOINT=${var.postgres_s3_endpoint_url}",
                      "DUMP_BUCKET=${var.postgres_dump_bucket}",
                      "DUMP_PATH=" + dumpPath
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

database_restore_script = <<-SCRIPT
    #!/usr/bin/env bash
    set -Eeuo pipefail
    set +x

    filter_sql_for_postgres_11() {
      sed \
        -e '/^\\restrict[[:space:]]/d' \
        -e '/^\\unrestrict[[:space:]]/d' \
        -e '/^SET transaction_timeout[[:space:]]*=/d' \
        -e '/^SET default_table_access_method[[:space:]]*=/d'
    }

    verify_compatibility_filter() {
      local actual expected
      actual="$({
        printf '%s\n' '\restrict token'
        printf '%s\n' 'SET transaction_timeout = 0;'
        printf '%s\n' 'SET default_table_access_method = heap;'
        printf '%s\n' 'SELECT 1;'
        printf '%s\n' '\unrestrict token'
      } | filter_sql_for_postgres_11)"
      expected='SELECT 1;'
      if [[ "$actual" != "$expected" ]]; then
        echo 'Internal PostgreSQL 11 compatibility-filter self-test failed' >&2
        exit 3
      fi
    }

    restore_plain_sql() {
      echo 'Streaming PostgreSQL 11-compatible SQL backup into psql'
      filter_sql_for_postgres_11 |
        psql -X --quiet --dbname="$TARGET_DATABASE" --set=ON_ERROR_STOP=1 >/dev/null
    }

    export PGUSER="$(cat .db-user)"
    export PGPASSWORD="$(cat .db-password)"
    export PGOPTIONS='-c statement_timeout=0 -c lock_timeout=300000'

    echo "Restore client: $(psql --version)"
    echo "Target server: $(psql -X --dbname="$TARGET_DATABASE" --tuples-only --no-align --command='SHOW server_version')"
    verify_compatibility_filter

    case "$DUMP_OBJECT" in
      *.sql.gz|*.gz)
        echo 'Validating the complete compressed SQL backup before changing the database'
        gzip --test restore.input.gz
        ;;
      *.sql)
        test -s restore.input
        ;;
      *.dump)
        pg_restore --list restore.input >/dev/null
        ;;
      *)
        echo "Unsupported dump format: $DUMP_OBJECT" >&2
        exit 2
        ;;
    esac

    if [[ "$VALIDATE_ONLY" == 'true' ]]; then
      echo 'Backup and database preflight validation completed'
      exit 0
    fi

    if [[ "$RESET_SCHEMA" == 'true' ]]; then
      : > .database-reset-started
      echo 'Terminating remaining connections owned by the restore role'
      psql -X --dbname="$TARGET_DATABASE" --set=ON_ERROR_STOP=1 \
        --command="SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND usename = current_user AND pid <> pg_backend_pid();" \
        >/dev/null
      psql -X --dbname="$TARGET_DATABASE" --set=ON_ERROR_STOP=1 \
        --command='DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public AUTHORIZATION CURRENT_USER;'
    fi

    case "$DUMP_OBJECT" in
      *.sql.gz|*.gz)
        gzip --decompress --stdout restore.input.gz | restore_plain_sql
        ;;
      *.sql)
        restore_plain_sql < restore.input
        ;;
      *.dump)
        pg_restore --no-owner --no-acl --clean --if-exists --exit-on-error \
          --dbname="$TARGET_DATABASE" restore.input
        ;;
    esac

    table_count="$(psql -X --dbname="$TARGET_DATABASE" --tuples-only --no-align \
      --command="SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname = 'public'")"
    echo "Restored public tables: $table_count"
    if [[ ! "$table_count" =~ ^[1-9][0-9]*$ ]]; then
      echo 'Restore verification failed: the public schema contains no tables' >&2
      exit 4
    fi
  SCRIPT

database_restore_job_script = <<-EOT
    pipelineJob('aof-db-restore') {
      description('Restores a PostgreSQL dump from S3 into the selected AOF instance database.')
      keepDependencies(false)
      properties {
        disableConcurrentBuilds()
      }
      parameters {
        choiceParam('INSTANCE', ${jsonencode(var.frontend_instances)}, 'Deployment instance and namespace suffix.')
        stringParam('DUMP_OBJECT', '', 'Object key inside ${var.postgres_dump_bucket}, for example production/automatic/nsbackup-2026-07-17.gz or feature/manual/aof-manual-20260525T120000Z.dump.')
        stringParam('TARGET_DATABASE', 'aof', 'Database to restore into.')
        booleanParam('RESET_SCHEMA', true, 'Drop and recreate public schema before restoring.')
      }
      definition {
        cps {
          sandbox(true)
          script('''
            lock(resource: 'aof-stand-' + params.INSTANCE, reason: 'Database restore for ' + params.INSTANCE) {
              currentBuild.description = 'Waiting up to 15 minutes for autoscaled CI capacity'
              echo 'Database restores require a dedicated CI node and never fall back to application workers.'

              podTemplate(serviceAccount: 'jenkins', slaveConnectTimeout: 900, workspaceVolume: dynamicPVC(accessModes: 'ReadWriteOnce', requestsSize: '64Gi', storageClassName: 'universal2.ru-7a'), yaml: """
            apiVersion: v1
            kind: Pod
            spec:
              securityContext:
                fsGroup: 1000
                fsGroupChangePolicy: OnRootMismatch
              nodeSelector:
                workload: ci
              tolerations:
                - key: dedicated
                  operator: Equal
                  value: ci
                  effect: NoSchedule
              containers:
                - name: jnlp
                  image: jenkins/inbound-agent:latest-jdk21
                - name: postgres
                  image: postgres:11
                  command:
                    - cat
                  tty: true
                  volumeMounts:
                    - name: restore-script
                      mountPath: /opt/aof-restore
                      readOnly: true
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
              volumes:
                - name: restore-script
                  configMap:
                    name: aof-db-restore-script
            """) {
              node(POD_LABEL) {
                currentBuild.description = 'CI agent allocated'
                echo 'CI agent is ready; starting the build.'
                def namespace = 'aof-' + params.INSTANCE
                def clusterName = 'aof-' + params.INSTANCE + '-db'
                def backendReplicas = null
                def restoreCompleted = false

                try {
                  stage('Prepare Secrets') {
                    container('kubectl') {
                      withEnv([
                        "NAMESPACE=" + namespace,
                        "DB_SECRET=" + clusterName + "-app"
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
                        "DUMP_OBJECT=" + params.DUMP_OBJECT
                      ]) {
                        sh 'set +x; set -eu; test -n "$DUMP_OBJECT"; export S3_ACCESS_KEY=$(cat .s3-access-key); export S3_SECRET_KEY=$(cat .s3-secret-key); mc alias set target "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY"; mc stat "target/$DUMP_BUCKET/$DUMP_OBJECT" >/dev/null; case "$DUMP_OBJECT" in *.sql.gz|*.gz) mc cp "target/$DUMP_BUCKET/$DUMP_OBJECT" restore.input.gz; ls -lh restore.input.gz ;; *) mc cp "target/$DUMP_BUCKET/$DUMP_OBJECT" restore.input; ls -lh restore.input ;; esac'
                      }
                    }
                  }

                  stage('Validate Backup') {
                    container('postgres') {
                      withEnv([
                        "PGHOST=" + clusterName + "-rw." + namespace + ".svc.cluster.local",
                        "PGPORT=5432",
                        "TARGET_DATABASE=" + params.TARGET_DATABASE,
                        "RESET_SCHEMA=" + params.RESET_SCHEMA,
                        "DUMP_OBJECT=" + params.DUMP_OBJECT,
                        "VALIDATE_ONLY=true"
                      ]) {
                        sh 'bash /opt/aof-restore/restore.sh'
                      }
                    }
                  }

                  if (params.RESET_SCHEMA) {
                    stage('Quiesce Backend') {
                      container('kubectl') {
                        withEnv(["NAMESPACE=" + namespace]) {
                          backendReplicas = sh(
                            returnStdout: true,
                            script: 'set -eu; kubectl -n "$NAMESPACE" get deployment aof-back -o jsonpath="{.spec.replicas}"'
                          ).trim()
                          if (!(backendReplicas ==~ /^[0-9]+$/)) {
                            error("Invalid aof-back replica count: " + backendReplicas)
                          }
                          withEnv(["BACKEND_REPLICAS=" + backendReplicas]) {
                            sh 'set -eu; if [ "$BACKEND_REPLICAS" -gt 0 ]; then kubectl -n "$NAMESPACE" patch deployment aof-back --type=merge -p "{\\\\\"spec\\\\\":{\\\\\"replicas\\\\\":0}}"; kubectl -n "$NAMESPACE" wait --for=delete pod -l app.kubernetes.io/instance=aof-back,app.kubernetes.io/name=aof-back --timeout=300s; else echo "aof-back is already scaled to zero"; fi'
                          }
                        }
                      }
                    }
                  }

                  stage('Restore') {
                    container('postgres') {
                      withEnv([
                        "PGHOST=" + clusterName + "-rw." + namespace + ".svc.cluster.local",
                        "PGPORT=5432",
                        "TARGET_DATABASE=" + params.TARGET_DATABASE,
                        "RESET_SCHEMA=" + params.RESET_SCHEMA,
                        "DUMP_OBJECT=" + params.DUMP_OBJECT,
                        "VALIDATE_ONLY=false",
                        "S3_ENDPOINT=${var.postgres_s3_endpoint_url}",
                        "DUMP_BUCKET=${var.postgres_dump_bucket}"
                      ]) {
                        sh 'bash /opt/aof-restore/restore.sh'
                        restoreCompleted = true
                      }
                    }
                  }
                } finally {
                  if (backendReplicas != null) {
                    if (restoreCompleted || !fileExists('.database-reset-started')) {
                      stage('Resume Backend') {
                        container('kubectl') {
                          withEnv([
                            "NAMESPACE=" + namespace,
                            "BACKEND_REPLICAS=" + backendReplicas
                          ]) {
                            sh 'set -eu; kubectl -n "$NAMESPACE" patch deployment aof-back --type=merge -p "{\\\\\"spec\\\\\":{\\\\\"replicas\\\\\":$BACKEND_REPLICAS}}"; if [ "$BACKEND_REPLICAS" -gt 0 ]; then kubectl -n "$NAMESPACE" rollout status deployment/aof-back --timeout=1200s; fi'
                          }
                        }
                      }
                    } else {
                      echo 'Restore did not complete after schema mutation started; leaving aof-back scaled down to protect the partially restored database.'
                    }
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
  local.database_dump_job_script,
  local.database_restore_job_script
], local.frontend_job_scripts, local.backend_job_scripts, var.extra_job_scripts)
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

resource "kubernetes_config_map" "backend_chart" {
  metadata {
    name      = local.backend_chart_name
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  data = local.backend_chart_data
}

resource "kubernetes_config_map" "backend_tools" {
  lifecycle {
    create_before_destroy = true
  }
  metadata {
    name      = local.backend_tools_name
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }
  data = local.backend_tools_data
}

resource "kubernetes_config_map" "database_restore_script" {
  metadata {
    name      = "aof-db-restore-script"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  data = {
    "restore.sh" = local.database_restore_script
  }
}

resource "helm_release" "jenkins" {
  depends_on = [kubernetes_config_map.backend_tools]

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
          "backend-console-filter" = <<-SCRIPT
            import jenkins.model.Jenkins
            def jenkins = Jenkins.get()
            System.setProperty('aof.backendJobName', '${var.backend_job_name}')
            if (jenkins.pluginManager.getPlugin('aof-backend-console') == null) {
              def pluginFile = new File(jenkins.rootDir, 'plugins/aof-backend-console.jpi')
              pluginFile.bytes = '${filebase64("${path.module}/console-filter/aof-backend-console.hpi")}'.decodeBase64()
              jenkins.pluginManager.dynamicLoad(pluginFile)
              println('Installed scoped AOF backend console formatter')
            }
          SCRIPT

          "backend-console-view" = <<-SCRIPT
            import jenkins.model.Jenkins
            def jenkins = Jenkins.get()
            def pluginFile = new File(jenkins.rootDir, 'plugins/aof-backend-console-view.jpi')
            pluginFile.bytes = '${filebase64("${path.module}/console-view/aof-backend-console-view.hpi")}'.decodeBase64()
            if (jenkins.pluginManager.getPlugin('aof-backend-console-view') == null) {
              jenkins.pluginManager.dynamicLoad(pluginFile)
            }
            // Static UI updates can be served immediately; the Java extension is unchanged.
            def asset = new File(jenkins.rootDir, 'plugins/aof-backend-console-view/console.js')
            asset.bytes = '${filebase64("${path.module}/console-view/web/console.js")}'.decodeBase64()
          SCRIPT

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
          "job-dsl:latest",
          "lockable-resources:1539.v4db_b_fc1cc115"
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
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
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
