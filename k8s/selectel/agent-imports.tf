import {
  to = module.aof_agent.kubernetes_namespace_v1.agent
  id = "aof-agent"
}

import {
  to = module.aof_agent.kubernetes_resource_quota_v1.agent
  id = "aof-agent/agent-budget"
}

import {
  to = module.aof_agent.kubernetes_network_policy_v1.default_deny
  id = "aof-agent/default-deny"
}

import {
  to = module.aof_agent.helm_release.agent["telegram"]
  id = "aof-agent/aof-agent-telegram"
}

import {
  to = module.aof_agent.helm_release.agent["coding"]
  id = "aof-agent/aof-agent-coding"
}

import {
  to = module.aof_agent.helm_release.agent["database"]
  id = "aof-agent/aof-agent-db"
}

import {
  to = module.aof_agent.helm_release.agent["workspace"]
  id = "aof-agent/aof-agent-workspace"
}

import {
  to = module.aof_agent.helm_release.agent["worker"]
  id = "aof-agent/aof-agent-worker"
}
