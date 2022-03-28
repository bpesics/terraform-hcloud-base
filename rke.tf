provider "rke" {
  log_file = "rke_debug.log"
}

# https://github.com/rancher/terraform-provider-rke/tree/master/examples
resource "rke_cluster" "this" {
  depends_on = [
    null_resource.server_init
  ]

  cluster_name = var.ENV.name.prefix
  # https://github.com/rancher/rke/releases
  kubernetes_version = "v1.20.11-rancher1-1"

  ssh_agent_auth = true

  dynamic "nodes" {
    for_each = var.servers
    content {
      # once again: some CNI doesn't work properly between nodes by default because some traffic wants to go via the eth0 public interfaces instead of the internal
      # https://github.com/hetznercloud/hcloud-cloud-controller-manager/issues/90#issuecomment-704787617
      # https://github.com/rancher/rke/issues/363

      # needs to be set to the same as it is on the cloud console
      hostname_override = hcloud_server.this[nodes.key].name

      # if internal_address is not set address is used for inter-host communication
      # RKE must be able to connect to this address
      # address = hcloud_server.this[nodes.key].ipv4_address
      address = nodes.value["ip_internal"]
      # this would put the inter-host communication on the internal network but because RKE connects to hosts on the address
      # it's easier to just use the private address as the main address
      # internal_address = nodes.value["ip_internal"]

      user = "root"
      role = nodes.value["roles"]
    }
  }

  # kube-apiserver is not available on the external ip address as we only allow the port TCP 22 for SSH
  # therefore let RKE ssh in for access...
  bastion_host {
    address = hcloud_server.this["control-1"].ipv4_address
    user    = "root"
  }


  # install ingress-nginx ourselves later
  ingress {
    provider = "none"
  }

  # install metrics-server outselves later...
  monitoring {
    provider = "none"
  }

  # draining upgrade would only be successful if there are enough nodes and pods were not restricted to specific workers
  # upgrade_strategy {
  #   drain                  = true
  #   max_unavailable_worker = "50%"
  #   drain_input {
  #     ignore_daemon_sets = true
  #     delete_local_data  = true
  #     force              = true
  #   }
  # }

  # the CNI would use the interface of the default gw
  # so it is necessary to explicitly specify the internal interface
  # (which is a cluser wide setting, so nodes needs to be the same in this regard)
  # https://github.com/rancher/rancher/issues/22584#issuecomment-698826330
  # canal_network_provider {
  #   iface = "ens10"
  # }
  # 
  # Weave works as well
  network {
    plugin = "calico"
  }

  # Warning: https://github.com/hetznercloud/hcloud-cloud-controller-manager/issues/4
  cloud_provider {
    name = "external"
  }

  services {
    kube_api {
      extra_args = {
        # just adding PodNodeSelector
        enable-admission-plugins = "NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota,NodeRestriction,Priority,TaintNodesByCondition,PersistentVolumeClaimResize,PodNodeSelector"
      }
    }
  }

  # https://github.com/hetznercloud/hcloud-cloud-controller-manager/blob/master/internal/annotation/load_balancer.go
  # https://github.com/hetznercloud/hcloud-cloud-controller-manager/blob/master/docs/load_balancers.md#cluster-wide-defaults
  # https://github.com/hetznercloud/hcloud-cloud-controller-manager/blob/master/hcloud/cloud.go#L33
  addons = <<-EOL
    apiVersion: v1
    kind: Secret
    metadata:
      name: hcloud
      namespace: kube-system
    stringData:
      debug: "false"
      token: "${var.hcloud_ccm_api_token}"
      network: "${hcloud_network.this.id}"
      lb_location: "${hcloud_server.this["control-1"].location}"
      # connect to worker nodes on their private address
      lb_use_private_ip: "true"
      # by default hetzner ccm returns (status.loadBalancer.ingress) multiple addresses for the LoadBalancer type ingress service (internal, external ipv4, external ipv6)
      # which external-dns can't handle (more precisely Route53 or other provider plugins)
      # this removes the ipv6 from the list
      lb_disable_ipv6: "true"
      # this removes the local address of the LB from the list
      lb_disable_private_ingress: "true"
    
    # https://github.com/hetznercloud/hcloud-cloud-controller-manager/issues/191
    ---
    apiVersion: v1
    kind: Secret
    metadata:
      name: hcloud-csi
      namespace: kube-system
    stringData:
      token: "${var.hcloud_ccm_api_token}"
    ---
    ${local.hcloud_ccm_yaml}
EOL

  # these are not needed anymore as there are good default toleration settings in RKE now
  # kubectl -n kube-system patch daemonset canal --type json -p '[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.cloudprovider.kubernetes.io/uninitialized","value":"true","effect":"NoSchedule"}}]'
  # kubectl -n kube-system patch deployment coredns --type json -p '[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.cloudprovider.kubernetes.io/uninitialized","value":"true","effect":"NoSchedule"}}]'
  addons_include = [
    "https://raw.githubusercontent.com/hetznercloud/csi-driver/v1.6.0/deploy/kubernetes/hcloud-csi.yml"
  ]

}

resource "kubernetes_manifest" "storage_class_retained" {
  depends_on = [rke_cluster.this]
  manifest = yamldecode(
    <<-EOF
    kind: StorageClass
    apiVersion: storage.k8s.io/v1
    metadata:
      name: hcloud-volumes-retained
    provisioner: csi.hetzner.cloud
    volumeBindingMode: Immediate
    allowVolumeExpansion: true
    reclaimPolicy: Retain
  EOF
  )
}

# pick a random port for ssh port forwarding
resource "random_integer" "ssh_listen_port" {
  min = 50000
  max = 60000
}

# instead of using rke_cluster.this.kube_config_yaml create this ourselves
# to be able to specify the endpoint
resource "local_file" "rke_kube_config" {
  filename        = "${path.root}/../../kubernetes/.kube_config"
  file_permission = "0600"
  content = templatefile(
    "${path.module}/templates/kube_config.tpl",
    {
      cluster_name = rke_cluster.this.cluster_name
      # localhost for ssh tunneling
      endpoint        = "127.0.0.1:${tostring(random_integer.ssh_listen_port.result)}"
      user_name       = "${rke_cluster.this.kube_admin_user}-${rke_cluster.this.cluster_name}"
      cluster_ca      = base64encode(rke_cluster.this.ca_crt)
      client_cert     = base64encode(rke_cluster.this.client_cert)
      client_cert_key = base64encode(rke_cluster.this.client_key)
    }
  )
}

locals {
  rke_kubectl_ssh_options = "-fNT -L ${tostring(random_integer.ssh_listen_port.result)}:localhost:6443 root@${hcloud_server.this["control-1"].ipv4_address}"
}
