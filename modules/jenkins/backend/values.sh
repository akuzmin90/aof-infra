#!/usr/bin/env bash
set -eu
set +x
cat <<EOF
fullnameOverride: aof-back
springProfile: $SPRING_PROFILE
image:
  repository: $IMAGE_REPOSITORY
  tag: $IMAGE_TAG
  digest: $IMAGE_DIGEST
  pullPolicy: Always
imagePullSecrets:
  - name: selectel-registry
extraVolumeMounts:
  - name: admin-data
    mountPath: /admin
extraVolumes:
  - name: admin-data
    persistentVolumeClaim:
      claimName: $ADMIN_PVC
database:
  url: jdbc:postgresql://$DB_CLUSTER-rw.$NAMESPACE.svc.cluster.local:5432/aof
  existingSecret: $DB_SECRET
resources:
  requests:
    cpu: 200m
    memory: $BACKEND_MEMORY_REQUEST
  limits:
    cpu: "2"
    memory: $BACKEND_MEMORY_LIMIT
startupProbe:
  failureThreshold: $STARTUP_FAILURE_THRESHOLD
  periodSeconds: 5
  timeoutSeconds: 3
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "16m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  hosts:
    - host: $HOST
      paths:
        - path: /api
          pathType: Prefix
    - host: $LEGACY_HOST
      paths:
        - path: /api
          pathType: Prefix
  tls:
    - secretName: $TLS_SECRET
      hosts:
        - $HOST
    - secretName: $LEGACY_TLS_SECRET
      hosts:
        - $LEGACY_HOST
podAnnotations:
  ci.aof/build: "$BUILD_ID"
EOF
