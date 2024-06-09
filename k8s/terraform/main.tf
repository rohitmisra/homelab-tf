terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.7.4"
    }
    ansible = {
      version = "~> 1.3.0"
      source  = "ansible/ansible"
    }
  }
  backend "s3" {
    bucket = "homelab-tf"
    key    = "k8s/state/terraform.tfstate"
  }
}

provider "proxmox" {
  pm_api_url        = var.pm_api_url
  pm_tls_insecure   = "true"
  pm_parallel       = 3
}

resource "proxmox_vm_qemu" "k3s_server" {
  count             = 1
  name              = "kubernetes-master-${count.index}"
  target_node       = var.pm_target_node

  # Activate QEMU agent for this VM
  agent             = 1

  clone             = "ubuntu-2004-cloudinit-template"

  os_type           = "cloud-init"
  cores             = 4
  sockets           = "1"
  cpu               = "host"
  memory            = 2048
  scsihw            = "virtio-scsi-pci"
  bootdisk          = "scsi0"

  disk {
    size            = "20G"
    type            = "scsi"
    storage         = "Local-Proxmox"
    iothread        = 1
  }

  network {
    model           = "virtio"
    bridge          = "vmbr0"
  }

  # Cloud Init Settings
  ipconfig0         = "ip=${var.master_ip}/24,gw=192.168.178.1"
  
  // DNS Settings
  searchdomain = "fritz.box"
  nameserver   = "192.168.178.1"

  sshkeys = <<EOF
  ${var.ssh_pub_key}
  EOF

  #creates ssh connection to check when the VM is ready for ansible provisioning
  connection {
    host        = var.master_ip
    user        = "ubuntu"
    private_key = file(var.ssh_pvt_key_location)
    agent       = false
    timeout     = "3m"
  }

  provisioner "remote-exec" {
    inline = ["echo Done!"]
  }
}

resource "proxmox_vm_qemu" "k3s_agent" {
  count             = 2
  name              = "kubernetes-node-${count.index}"
  target_node       = var.pm_target_node

  # Activate QEMU agent for this VM
  agent             = 1

  clone             = "ubuntu-2004-cloudinit-template"

  os_type           = "cloud-init"
  cores             = 4
  sockets           = "1"
  cpu               = "host"
  memory            = 4096
  scsihw            = "virtio-scsi-pci"
  bootdisk          = "scsi0"

  disk {
    size            = "20G"
    type            = "scsi"
    storage         = "Local-Proxmox"
    iothread        = 1
  }

  network {
    model           = "virtio"
    bridge          = "vmbr0"
  }

  # Cloud Init Settings
  ipconfig0         = "ip=${var.worker_ips[count.index]}/24,gw=192.168.178.1"
  // DNS Settings
  searchdomain = "fritz.box"
  nameserver   = "192.168.178.1"

  sshkeys = <<EOF
  ${var.ssh_pub_key}
  EOF

  #creates ssh connection to check when the VM is ready for ansible provisioning
  connection {
    host        = var.worker_ips[count.index]
    user        = "ubuntu"
    private_key = file(var.ssh_pvt_key_location)
    agent       = false
    timeout     = "3m"
  }

  provisioner "remote-exec" {
    inline = ["echo Done!"]
  }
}

resource "ansible_host" "master_node" {
  name = var.master_ip
  groups = ["master_nodes"]
  variables = {
    ansible_user               = "ubuntu"
    ansible_ssh_private_key    = var.ssh_pvt_key_location
    ansible_python_interpreter = "/usr/bin/python3"
    ansible_ssh_extra_args  = "-o StrictHostKeyChecking=no"
    ansible_ssh_common_args ="'-o StrictHostKeyChecking=no'"
    // ansible_ssh_extra_args='-o StrictHostKeyChecking=no'
  }
   depends_on = [proxmox_vm_qemu.k3s_agent]
}

resource "ansible_host" "worker_nodes" {
  count = length(var.worker_ips)
  name  = var.worker_ips[count.index]
  groups = ["worker_nodes"]
  variables = {
    ansible_user               = "ubuntu"
    ansible_ssh_private_key    = var.ssh_pvt_key_location
    ansible_python_interpreter = "/usr/bin/python3"
    ansible_ssh_common_args    = "-o StrictHostKeyChecking=no"
    ansible_ssh_extra_args     = "-o StrictHostKeyChecking=no"
    ansible_ssh_common_args    ="'-o StrictHostKeyChecking=no'"
  }
   depends_on = [proxmox_vm_qemu.k3s_agent]
}

resource "ansible_playbook" "master_playbook" {
  name          = ansible_host.master_node.name
  playbook      = "../ansible/master-playbook.yml"
  extra_vars = {
    rancherip         = var.rancher_ip
    ranchertoken      = var.rancher_token
    ranchercachecksum = var.rancher_ca_checksum
    nodename          = "kubernetes-master"
    nodeip            = var.master_ip
    ansible_ssh_common_args    = "-o StrictHostKeyChecking=no"
    ansible_ssh_extra_args     = "-o StrictHostKeyChecking=no"
    //ansible_ssh_common_args    ="'-o StrictHostKeyChecking=no'"
  }
  depends_on = [ansible_host.master_node]
}

resource "ansible_playbook" "worker_playbook" {
  count         = length(var.worker_ips)
  name          = ansible_host.worker_nodes[count.index].name
  playbook      = "../ansible/worker-playbook.yml"
  extra_vars = {
    rancherip         = var.rancher_ip
    ranchertoken      = var.rancher_token
    ranchercachecksum = var.rancher_ca_checksum
    nodename          = "kubernetes-worker-${count.index}"
    nodeip            = var.worker_ips[count.index]
    ansible_ssh_common_args    = "-o StrictHostKeyChecking=no"
    ansible_ssh_extra_args     = "-o StrictHostKeyChecking=no"
    //ansible_ssh_common_args    ="'-o StrictHostKeyChecking=no'"
  }
  depends_on = [ansible_host.worker_nodes]
}