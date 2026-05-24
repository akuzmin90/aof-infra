properties([
  disableConcurrentBuilds(),
  parameters([
    string(name: 'BRANCH', defaultValue: 'master', description: 'Git branch to deploy.'),
    string(name: 'GIT_CREDENTIALS_ID', defaultValue: '', description: 'Optional Jenkins credential ID for private Git repositories.'),
    string(name: 'BUILD_COMMAND', defaultValue: 'npm run build', description: 'Frontend build command.')
  ])
])

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
