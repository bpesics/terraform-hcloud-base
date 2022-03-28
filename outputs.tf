output "rke" {
  value = {
    nodes               = local.servers
    kubectl_ssh_options = local.rke_kubectl_ssh_options
  }
}
