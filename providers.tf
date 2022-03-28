terraform {

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.3"
    }

    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.32.1"
    }

    rke = {
      source  = "rancher/rke"
      version = "1.2.4"
    }
  }

}
