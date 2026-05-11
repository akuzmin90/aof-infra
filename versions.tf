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
      version = "~> 7.0"
    }
  }
}
