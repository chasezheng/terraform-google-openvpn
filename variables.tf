variable "project_id" {
  description = "The GCP Project ID"
  default     = null
}

variable "name" {
  type        = string
  description = "The name to use when generating resources"
}

variable "region" {
  description = "The GCP Project Region"
  default     = null
}

variable "zone" {
  description = "The GCP Zone to deploy VPN Compute instance to"
}

variable "network" {
  description = "The name or self_link of the network to attach this interface to. Use network attribute for Legacy or Auto subnetted networks and subnetwork for custom subnetted networks."
  default     = "default"
}

variable "subnetwork" {
  description = "The name of the subnetwork to attach this interface to. The subnetwork must exist in the same region this instance will be created in. Either network or subnetwork must be provided."
  default     = null
}

variable "service_account" {
  default = null
  type = object(
    {
      email  = string,
      scopes = set(string)
    }
  )
  description = "Service account to attach to the instance. See https://www.terraform.io/docs/providers/google/r/compute_instance_template.html#service_account."
}

variable "metadata" {
  description = "Metadata, provided as a map"
  default     = {}
}

variable "network_tier" {
  description = "Network network_tier"
  default     = "STANDARD"
}

variable "labels" {
  default     = {}
  description = "Labels, provided as a map"
}

variable "users" {
  default     = []
  type        = list(string)
  description = "list of user to create"
}

variable "tags" {
  description = "network tags to attach to the instance"
  default     = []
}

variable "output_dir" {
  description = "Folder to store all user openvpn details"
  default     = "openvpn"
}

variable "remote_user" {
  description = "The user to operate as on the VM. SSH Key is generated for this user"
  default     = "ubuntu"
}

variable "machine_type" {
  description = "Machine type to create, e.g. n1-standard-1"
  default     = "e2-micro"
}

variable "route_only_private_ips" {
  description = "Routes only private IPs through the VPN (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)"
  default     = false
}

variable "install_script_url" {
  description = "Openvpn install script url."
  type        = string
  default     = "https://raw.githubusercontent.com/angristan/openvpn-install/b3b7593b2d4dd146f9c9da810bcec9b07a69c026/openvpn-install.sh"
}

variable "dns_servers" {
  description = "The DNS servers to be configured"
  default     = ["8.8.8.8", "8.8.4.4"]
  type        = list(string)
  validation {
    condition     = length(var.dns_servers) >= 1 || length(var.dns_servers) <= 2
    error_message = "The variable 'var.dns_servers' should be an array with 1 or 2 DNS entries only."
  }
}

variable "server_port" {
  default = 1194
  type    = number
}

variable "protocol" {
  default = "udp"
  type    = string
}