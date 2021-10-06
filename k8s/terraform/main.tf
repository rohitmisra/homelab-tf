terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "2.7.4"
    }
  }
  backend "s3" {
    bucket = "homelab-tf"
    key    = "k8s/state/terraform.tfstate"
    region = "eu-central-1"
  }
}
provider "proxmox" {
  pm_api_url        = var.pm_api_url
  pm_tls_insecure = "true"
  pm_parallel = 3
}

resource "proxmox_vm_qemu" "k3s_server" {
  count             = 1
  name              = "kubernetes-master-${count.index}"
  target_node = "hv-pxe-01"
  # Activate QEMU agent for this VM
  agent = 1

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

  sshkeys = <<EOF
  ${var.ssh_key}
  EOF

  #creates ssh connection to check when the VM is ready for ansible provisioning
  connection {
    host = var.master_ip
    user = "ubuntu"
    private_key = file(var.ssh_key_location)
    agent = false
    timeout = "3m"
  }

  provisioner "remote-exec" {
    inline = ["echo Done!"]
  }

  provisioner "local-exec" {
    working_dir = "../ansible/"
    command = "ansible-playbook --ssh-common-args='-o StrictHostKeyChecking=no' -u ubuntu --key-file ${var.ssh_key_location} -i '${var.master_ip},' master-playbook.yml --extra-vars \"rancherip=${var.rancher_ip} ranchertoken=${var.rancher_token} ranchercachecksum=${var.rancher_ca_checksum} nodename='kubernetes-master-${count.index}' nodeip='${var.master_ip}'\""
  }

}

resource "proxmox_vm_qemu" "k3s_agent" {
  count             = 2
  name              = "kubernetes-node-${count.index}"
  target_node = "hv-pxe-01"

  # Activate QEMU agent for this VM
  agent = 1

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

  sshkeys = <<EOF
  ${var.ssh_key}
  EOF

  #creates ssh connection to check when the VM is ready for ansible provisioning
  connection {
    host = var.worker_ips[count.index]
    user = "ubuntu"
    private_key = file(var.ssh_key_location)
    agent = false
    timeout = "3m"
  }

  provisioner "remote-exec" {
    inline = ["echo Done!"]
  }

  provisioner "local-exec" {
    working_dir = "../ansible/"
    command = "ansible-playbook --ssh-common-args='-o StrictHostKeyChecking=no' -u ubuntu --key-file ${var.ssh_key_location} -i '${var.worker_ips[count.index]},' worker-playbook.yml --extra-vars \"rancherip=${var.rancher_ip} ranchertoken=${var.rancher_token} ranchercachecksum=${var.rancher_ca_checksum} nodename='kubernetes-worker-${count.index}' nodeip='${var.worker_ips[count.index]}'\""
  }

}
