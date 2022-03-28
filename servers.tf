resource "hcloud_server" "this" {
  for_each = var.servers

  depends_on = [
    hcloud_network_subnet.main,
  ]

  name        = "${var.ENV.name.prefix}-${each.key}"
  server_type = each.value["type"]
  image       = each.value["image"]
  location    = each.value["location"]
  ssh_keys    = [hcloud_ssh_key.bootstrap.id]
  backups     = true

  network {
    network_id = hcloud_network.this.id
    ip         = each.value["ip_internal"]
  }

  labels = var.ENV.common_tags
}

locals {
  servers = {
    for k, v in hcloud_server.this : k => {
      name        = v.name
      ip_internal = var.servers[k].ip_internal
      ip_address  = v.ipv4_address
    }
  }
}

resource "null_resource" "server_init" {
  for_each = hcloud_server.this

  connection {
    host = each.value["ipv4_address"]
    type = "ssh"
    user = "root"
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
        apt-get -yq update
        apt-get install -yq \
            ca-certificates \
            curl \
            gnupg \
            lsb-release \
            ntp \
            tree
        # https://docs.docker.com/engine/install/debian/
        curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install docker-ce docker-ce-cli containerd.io
        until docker info; do sleep 5; done
      EOF
    ]
  }

}