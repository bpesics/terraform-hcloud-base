variable "ENV" {
  type = object({
    name            = map(string)
    common_tags     = map(string)
    kubeconfig_path = string
  })

  description = "These values are environment specific and are in a single object to simplify high level data exchange."
}

variable "servers" {
  type = any
}

variable "hcloud_ccm_api_token" {
  type        = string
  description = "https://github.com/hetznercloud/hcloud-cloud-controller-manager"
  # + https://github.com/colinwilson/terraform-kubernetes-hcloud-csi-driver/
}

variable "bootstrap_ssh_key" {
  type        = string
  description = "path to the public key to deploy on servers for bootstrapping"
  default     = "~/.ssh/id_rsa.pub"
}

variable "hcloud_network_range" {
  type        = string
  description = "value"
  default     = "10.10.0.0/16"
}

variable "hcloud_subnet_range" {
  type        = string
  description = "value"
  default     = "10.10.0.0/24"
}

variable "hcloud_ccm_version" {
  type        = string
  description = "version tag of the container image hetznercloud/hcloud-cloud-controller-manager"
  default     = "v1.12.1"
}

variable "hcloud_csi_version" {
  type        = string
  description = "version in csi deploy yaml url https://github.com/hetznercloud/csi-driver/releases"
  default     = "v1.6.0"
}
