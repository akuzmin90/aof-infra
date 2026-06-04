terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    endpoints = {
      s3 = "https://s3.ru-7.storage.selcloud.ru"
    }
    key                         = "aof-infra.tfstate"
    region                      = "ru-7"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_metadata_api_check     = true
    use_path_style              = true
  }

  required_providers {
    selectel = {
      source  = "selectel/selectel"
      version = "~> 7.1.0"
    }

    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "3.0.0"
    }

  }
}

locals {
  frontend_bucket_names = {
    dev     = "hitmakers-aof-front-dev"
    feature = "hitmakers-aof-front-feature"
    release = "hitmakers-aof-front-release"
  }
}

moved {
  from = openstack_objectstorage_container_v1.frontend
  to   = openstack_objectstorage_container_v1.frontend_legacy
}

provider "selectel" {
  domain_name = var.selectel_domain_name
  username    = var.selectel_username
  password    = var.selectel_password
  auth_region = "ru-7"
  auth_url    = "https://cloud.api.selcloud.ru/identity/v3/"
}

provider "openstack" {
  auth_url    = "https://cloud.api.selcloud.ru/identity/v3"
  domain_name = var.selectel_domain_name
  tenant_id   = var.selectel_project_id
  user_name   = var.selectel_username
  password    = var.selectel_password
  region      = "ru-7"
}

resource "openstack_networking_network_v2" "k8s" {
  name           = "aof-k8s-network"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "k8s" {
  name            = "aof-k8s-subnet"
  network_id      = openstack_networking_network_v2.k8s.id
  cidr            = "192.168.199.0/24"
  dns_nameservers = ["188.93.16.19", "188.93.17.19"]
  enable_dhcp     = false
}

data "openstack_networking_network_v2" "external" {
  external = true
}

resource "openstack_networking_router_v2" "k8s" {
  name                = "aof-k8s-router"
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "k8s" {
  router_id = openstack_networking_router_v2.k8s.id
  subnet_id = openstack_networking_subnet_v2.k8s.id
}

data "selectel_mks_kube_versions_v1" "available" {
  project_id = var.selectel_project_id
  region     = "ru-7"
}

resource "selectel_mks_cluster_v1" "main" {
  name                              = "aof-k8s"
  project_id                        = var.selectel_project_id
  region                            = "ru-7"
  kube_version                      = data.selectel_mks_kube_versions_v1.available.latest_version
  zonal                             = true
  enable_patch_version_auto_upgrade = false
  network_id                        = openstack_networking_network_v2.k8s.id
  subnet_id                         = openstack_networking_subnet_v2.k8s.id
  maintenance_window_start          = "00:00:00"

  depends_on = [
    openstack_networking_router_interface_v2.k8s
  ]
}

resource "selectel_mks_nodegroup_v1" "compute" {
  cluster_id                   = selectel_mks_cluster_v1.main.id
  project_id                   = selectel_mks_cluster_v1.main.project_id
  region                       = selectel_mks_cluster_v1.main.region
  availability_zone            = "ru-7a"
  nodes_count                  = 2
  cpus                         = 2
  ram_mb                       = 8192
  volume_gb                    = 32
  volume_type                  = "fast.ru-7a"
  install_nvidia_device_plugin = false
  preemptible                  = false

  labels = {
    "hitmakers.ru/node-pool" = "compute"
    "workload"               = "compute"
  }
}

resource "selectel_mks_nodegroup_v1" "database" {
  cluster_id                   = selectel_mks_cluster_v1.main.id
  project_id                   = selectel_mks_cluster_v1.main.project_id
  region                       = selectel_mks_cluster_v1.main.region
  availability_zone            = "ru-7a"
  nodes_count                  = 1
  cpus                         = 4
  ram_mb                       = 16384
  volume_gb                    = 64
  volume_type                  = "fast.ru-7a"
  install_nvidia_device_plugin = false
  preemptible                  = false

  labels = {
    "hitmakers.ru/node-pool" = "database"
    "workload"               = "database"
  }

  taints {
    key    = "dedicated"
    value  = "database"
    effect = "NoSchedule"
  }
}

data "selectel_mks_kubeconfig_v1" "main" {
  cluster_id = selectel_mks_cluster_v1.main.id
  project_id = selectel_mks_cluster_v1.main.project_id
  region     = selectel_mks_cluster_v1.main.region
}

resource "selectel_craas_registry_v1" "main" {
  name       = "aof-registry"
  project_id = var.selectel_project_id
}

resource "selectel_craas_token_v2" "registry_rw" {
  project_id     = var.selectel_project_id
  name           = "aof-registry-rw"
  mode_rw        = true
  all_registries = false
  registry_ids   = [selectel_craas_registry_v1.main.id]
  is_set         = true
  expires_at     = "2029-01-01T00:00:00Z"
}

resource "openstack_objectstorage_container_v1" "frontend_instance" {
  for_each = local.frontend_bucket_names

  name           = each.value
  region         = "ru-7"
  container_read = ".r:*"
  force_destroy  = false
}

resource "openstack_objectstorage_container_v1" "frontend_legacy" {
  name           = "hitmakers-aof-front"
  region         = "ru-7"
  container_read = ".r:*"
  force_destroy  = false
}
