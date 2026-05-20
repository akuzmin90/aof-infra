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

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
  }
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

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "admin@aof-test-k8s"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "admin@aof-test-k8s"
  }
}

resource "openstack_networking_network_v2" "k8s" {
  name           = "aof-test-k8s-network"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "k8s" {
  name            = "aof-test-k8s-subnet"
  network_id      = openstack_networking_network_v2.k8s.id
  cidr            = "192.168.199.0/24"
  dns_nameservers = ["188.93.16.19", "188.93.17.19"]
  enable_dhcp     = false
}

data "openstack_networking_network_v2" "external" {
  external = true
}

resource "openstack_networking_router_v2" "k8s" {
  name                = "aof-test-k8s-router"
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

resource "selectel_mks_cluster_v1" "test" {
  name                              = "aof-test-k8s"
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

resource "selectel_mks_nodegroup_v1" "test" {
  cluster_id                   = selectel_mks_cluster_v1.test.id
  project_id                   = selectel_mks_cluster_v1.test.project_id
  region                       = selectel_mks_cluster_v1.test.region
  availability_zone            = "ru-7a"
  nodes_count                  = 1
  flavor_id                    = 1014
  volume_gb                    = 32
  volume_type                  = "fast.ru-7a"
  install_nvidia_device_plugin = false
  preemptible                  = false
}

data "selectel_mks_kubeconfig_v1" "test" {
  cluster_id = selectel_mks_cluster_v1.test.id
  project_id = selectel_mks_cluster_v1.test.project_id
  region     = selectel_mks_cluster_v1.test.region
}

resource "selectel_craas_registry_v1" "main" {
  name       = var.registry_name
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

module "ingress_nginx" {
  source = "./modules/ingress-nginx"
}

module "cert_manager" {
  source = "./modules/cert-manager"
}

module "jenkins" {
  source = "./modules/jenkins"

  admin_password = var.jenkins_admin_password
}
