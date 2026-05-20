pipeline {
  agent {
    kubernetes {
      defaultContainer 'node'
      yaml '''
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
'''
    }
  }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  parameters {
    string(name: 'BRANCH', defaultValue: 'master', description: 'Git branch to deploy.')
  }

  environment {
    FRONT_REPO = 'https://github.com/akuzmin90/aof-front.git'
    MINIO_ENDPOINT = 'http://minio.minio.svc.cluster.local:9000'
    MINIO_BUCKET = 'aof-front'
    MINIO_ACCESS_KEY = 'minioadmin'
    MINIO_SECRET_KEY = 'minioadmin123'
  }

  stages {
    stage('Checkout') {
      steps {
        git branch: params.BRANCH,
          credentialsId: 'github-aof-token',
          url: env.FRONT_REPO
      }
    }

    stage('Build') {
      steps {
        container('node') {
          sh '''
            set -eu
            npm install
            npm run build

            INDEX_FILE="$(find dist -maxdepth 1 -type f -name 'index*.html' ! -name 'index.html' | sort | tail -n 1)"
            if [ -z "$INDEX_FILE" ]; then
              echo "No versioned index*.html found in dist"
              exit 1
            fi

            cp "$INDEX_FILE" dist/index.html
            echo "Created stable index.html from $(basename "$INDEX_FILE")"
          '''
        }
      }
    }

    stage('Upload') {
      steps {
        container('mc') {
          sh '''
            set -eu
            mc alias set local "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"
            mc mb --ignore-existing "local/$MINIO_BUCKET"
            mc mirror --overwrite --remove dist "local/$MINIO_BUCKET"
            mc anonymous set download "local/$MINIO_BUCKET"
          '''
        }
      }
    }
  }
}
