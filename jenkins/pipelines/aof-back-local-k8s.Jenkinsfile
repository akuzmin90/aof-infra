properties([
  disableConcurrentBuilds(),
  parameters([
    string(name: 'BRANCH', defaultValue: 'master', description: 'Git branch to deploy.'),
    string(name: 'GIT_CREDENTIALS_ID', defaultValue: '', description: 'Optional Jenkins credential ID for private Git repositories.'),
    string(name: 'REGISTRY_SERVER', defaultValue: '', description: 'Registry host, for example cr.selcloud.ru. Required for private registry auth.'),
    string(name: 'REGISTRY_CREDENTIALS_ID', defaultValue: '', description: 'Optional Jenkins username/password credentials for registry push.'),
    string(name: 'IMAGE_REPOSITORY', defaultValue: '', description: 'Full image repository, for example cr.selcloud.ru/aof-registry/aof-back.'),
    string(name: 'IMAGE_TAG', defaultValue: '', description: 'Optional image tag. Defaults to branch-build_number.'),
    string(name: 'RELEASE_NAME', defaultValue: 'aof-back', description: 'Helm release name.'),
    string(name: 'NAMESPACE', defaultValue: 'aof', description: 'Kubernetes namespace.'),
    booleanParam(name: 'INGRESS_ENABLED', defaultValue: true, description: 'Expose backend under /api through ingress.')
  ])
])

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
        imageTag = "${params.BRANCH}-${env.BUILD_NUMBER}".replaceAll('[^A-Za-z0-9_.-]', '-')
      }

      imageRepository = params.IMAGE_REPOSITORY?.trim()
      if (!imageRepository) {
        error('IMAGE_REPOSITORY is required, for example cr.selcloud.ru/aof-registry/aof-back')
      }

      currentBuild.displayName = "#${env.BUILD_NUMBER} ${imageTag}"
    }

    stage('Build and Push Image') {
      container('kaniko') {
        withEnv([
          "IMAGE_REPOSITORY=${imageRepository}",
          "IMAGE_TAG=${imageTag}",
          "REGISTRY_SERVER=${params.REGISTRY_SERVER?.trim() ?: ''}"
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
          "IMAGE_REPOSITORY=${imageRepository}",
          "IMAGE_TAG=${imageTag}",
          "RELEASE_NAME=${params.RELEASE_NAME}",
          "NAMESPACE=${params.NAMESPACE}",
          "INGRESS_ENABLED=${params.INGRESS_ENABLED}"
        ]) {
          try {
            timeout(time: 16, unit: 'MINUTES') {
              sh 'set +x; set -eu; DB_PASSWORD=$(kubectl -n database get secret aof-db-app -o jsonpath="{.data.password}" | base64 -d); helm upgrade --install "$RELEASE_NAME" chart --namespace "$NAMESPACE" --create-namespace --set image.repository="$IMAGE_REPOSITORY" --set image.tag="$IMAGE_TAG" --set image.pullPolicy=IfNotPresent --set-string database.password="$DB_PASSWORD" --set ingress.enabled="$INGRESS_ENABLED" --wait --timeout 15m'
            }
          } catch (Exception deployFailure) {
            echo 'Deployment failed; collecting Kubernetes diagnostics (maximum 2 minutes).'
            try {
              timeout(time: 2, unit: 'MINUTES') {
                sh([
                  'set +x',
                  'SELECTOR="app.kubernetes.io/instance=$RELEASE_NAME"',
                  'echo "=== Deployment and pod status ==="',
                  'kubectl --request-timeout=10s -n "$NAMESPACE" get deployments,replicasets,pods -l "$SELECTOR" -o wide || true',
                  'echo "=== Pod details (scheduling, probes, exits, image pulls) ==="',
                  'kubectl --request-timeout=10s -n "$NAMESPACE" describe pods -l "$SELECTOR" || true',
                  'echo "=== Recent namespace events ==="',
                  'kubectl --request-timeout=10s -n "$NAMESPACE" get events --sort-by=.metadata.creationTimestamp | tail -n 80 || true',
                  'for pod in $(kubectl --request-timeout=10s -n "$NAMESPACE" get pods -l "$SELECTOR" -o name); do',
                  '  echo "=== $pod: current container logs ==="',
                  '  kubectl --request-timeout=10s -n "$NAMESPACE" logs "$pod" --all-containers=true --prefix=true --timestamps=true --tail=200 --pod-running-timeout=5s || true',
                  '  echo "=== $pod: previous container logs ==="',
                  '  kubectl --request-timeout=10s -n "$NAMESPACE" logs "$pod" --all-containers=true --prefix=true --timestamps=true --tail=200 --previous --pod-running-timeout=5s || true',
                  'done'
                ].join('\n'))
              }
            } catch (Exception diagnosticsFailure) {
              echo 'Diagnostics incomplete: ' + diagnosticsFailure.toString()
            }
            throw deployFailure
          }
        }
      }
    }
  }
}
