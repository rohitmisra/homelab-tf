variable "ssh_pvt_key_location" {
  default = "~/.ssh/id_rsa"
}
variable "pm_api_url" {
  default = ""
}

variable "pm_target_node" {
  default = ""
}

variable "master_ip" {
    description = "IP of the master node"
	  default     = ""
}

variable "worker_ips" {
    description = "IPs of the worker nodes"
    type        = list(string)
	  default     = []
}

variable "TF_VAR_ssh_pub_key" {
  default = ""
}

variable "rancher_ip" {
    description = "IP of the Rancher server"
	  default     = ""
}

variable "rancher_token" {
    description = "Token for Rancher access"
	  default     = ""
}

variable "rancher_ca_checksum" {
    description = "CA Checksum for Rancher access"
	  default     = ""
}