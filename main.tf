# Uses https://github.com/angristan/openvpn-install to setup VPN in a google VM
# creates and deletes users accordingly

locals {
  private_key_file = "private-key.pem"
  # adding the null_resource to prevent evaluating this until the openvpn_update_users has executed
  refetch_user_ovpn = null_resource.openvpn_update_users_script.id != "" ? !alltrue([for x in var.users : fileexists("${var.output_dir}/${x}.ovpn")]) : false
}

resource "google_compute_firewall" "allow-ingress-to-openvpn-server" {
  name        = "openvpn-${var.name}-allow-ingress"
  project     = var.project_id
  network     = var.network
  description = "Creates firewall rule targeting the openvpn instance"

  allow {
    protocol = "tcp"
    ports    = [var.server_port, "22"]
  }

  allow {
    protocol = "udp"
    ports    = [var.server_port]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["openvpn-${var.name}"]
}

resource "google_compute_address" "default" {
  name         = "openvpn-${var.name}-global-ip"
  project      = var.project_id
  region       = var.region
  network_tier = var.network_tier
}

resource "tls_private_key" "ssh-key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P521"
}

// SSH Private Key
resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ssh-key.private_key_pem
  filename        = "${var.output_dir}/${local.private_key_file}"
  file_permission = "0400"
}

resource "random_string" "openvpn_server_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "google_compute_instance" "openvpn_server" {
  name         = "openvpn-${var.name}-${random_string.openvpn_server_suffix.id}"
  project      = var.project_id
  machine_type = var.machine_type
  labels       = var.labels
  metadata = merge(
    var.metadata,
    { sshKeys = "${var.remote_user}:${tls_private_key.ssh-key.public_key_openssh}" }
  )
  zone = var.zone

  metadata_startup_script = <<SCRIPT
    curl -O ${var.install_script_url}
    chmod +x openvpn-install.sh
    mv openvpn-install.sh /home/${var.remote_user}/
    chown ${var.remote_user}:${var.remote_user} /home/${var.remote_user}/openvpn-install.sh
    export AUTO_INSTALL=y
    # Using Custom DNS
    export DNS=13
    export DNS1="${var.dns_servers[0]}"
    %{if length(var.dns_servers) > 1~}
    export DNS2="${var.dns_servers[1]}"
    %{endif~}
    export PORT_CHOICE=2
    export PORT=${var.server_port}
    export PROTOCOL_CHOICE=${var.protocol == "udp" ? 1 : 2}
    /home/${var.remote_user}/openvpn-install.sh
  SCRIPT

  boot_disk {
    auto_delete = true
    initialize_params {
      type  = "pd-standard"
      image = "ubuntu-minimal-2004-focal-v20220419a"
    }
  }

  dynamic "service_account" {
    for_each = var.service_account == null ? [] : [var.service_account]

    content {
      email  = try(each.value.email, null)
      scopes = try(each.scopes, [])
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    access_config {
      nat_ip       = google_compute_address.default.address
      network_tier = var.network_tier
    }
  }

  tags = toset(
    concat(var.tags, tolist(google_compute_firewall.allow-ingress-to-openvpn-server.target_tags))
  )

  provisioner "local-exec" {
    command = "ssh-keygen -R \"${self.network_interface[0].access_config[0].nat_ip}\" || true"
    when    = destroy
  }
}

# Updates/creates the users VPN credentials on the VPN server
resource "null_resource" "openvpn_update_users_script" {
  triggers = {
    users    = join(",", var.users)
    instance = google_compute_instance.openvpn_server.instance_id
  }

  connection {
    type        = "ssh"
    user        = var.remote_user
    host        = google_compute_address.default.address
    private_key = tls_private_key.ssh-key.private_key_pem
    agent       = false
    timeout     = "60s"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/update_users.sh"
    destination = "/home/${var.remote_user}/update_users.sh"
    when        = create
  }

  # Create New User with MENU_OPTION=1
  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /etc/openvpn/server.conf ]; do sleep 1; done",
      "while [ ! -f /etc/openvpn/client-template.txt ]; do sleep 1; done",
      "chmod +x ~${var.remote_user}/update_users.sh",
      "sudo REVOKE_ALL_CLIENT_CERTIFICATES=n ROUTE_ONLY_PRIVATE_IPS='${var.route_only_private_ips}' ~${var.remote_user}/update_users.sh ${join(" ", var.users)}",
    ]
    when = create
  }

  # Delete OVPN files if new instance is created
  provisioner "local-exec" {
    command = "rm -rf ${abspath(var.output_dir)}/*.ovpn"
    when    = create
  }

  depends_on = [google_compute_instance.openvpn_server, local_sensitive_file.private_key, tls_private_key.ssh-key]
}

# Download user configurations to output_dir
resource "null_resource" "openvpn_download_configurations" {
  triggers = {
    trigger = timestamp()
  }

  depends_on = [null_resource.openvpn_update_users_script]

  # Copy .ovpn config for user from server to var.output_dir
  provisioner "local-exec" {
    working_dir = var.output_dir
    command     = "${abspath(path.module)}/scripts/refetch_user.sh"
    environment = {
      REFETCH_USER_OVPN = local.refetch_user_ovpn
      PRIVATE_KEY_FILE  = local.private_key_file
      REMOTE_USER       = var.remote_user
      IP_ADDRESS        = google_compute_address.default.address
    }
    when = create
  }
}
