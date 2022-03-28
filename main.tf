resource "hcloud_network" "this" {
  name     = var.ENV.name.prefix
  ip_range = var.hcloud_network_range
}

resource "hcloud_network_subnet" "main" {
  network_id   = hcloud_network.this.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = var.hcloud_subnet_range
}

resource "hcloud_firewall" "main" {
  name = "${var.ENV.name.prefix}-main"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  dynamic "apply_to" {
    for_each = hcloud_server.this
    content {
      server = apply_to.value["id"]
    }
  }

}

resource "hcloud_ssh_key" "bootstrap" {
  name       = "bootstrap"
  public_key = file(var.bootstrap_ssh_key)
}