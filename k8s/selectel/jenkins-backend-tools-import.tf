# Created through the Kubernetes API while the S3 state backend was unavailable.
# Adopt it on the next normal apply instead of attempting to create it again.
# This block is an idempotent migration record; later tooling revisions can replace
# the imported resource normally once it is managed in state.
import {
  to = module.jenkins.kubernetes_config_map.backend_tools
  id = "jenkins/aof-back-ci-79697a3e5a13"
}
