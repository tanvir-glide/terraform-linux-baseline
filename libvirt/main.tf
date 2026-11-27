terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.1"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_volume" "ubuntu_base" {
  name   = "noble-base.qcow2"
  pool   = var.pool
  source = "${path.module}/${var.base_image}"
  format = "qcow2"
}

resource "libvirt_volume" "vm_disk" {
  name           = "${var.vm_name}-root.qcow2"
  pool           = var.pool
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = var.disk_bytes
}

resource "libvirt_cloudinit_disk" "init" {
  name      = "${var.vm_name}-cloudinit.iso"
  pool      = var.pool
  user_data = file("${path.module}/user-data.yaml")
}

resource "libvirt_domain" "vm" {
  name      = var.vm_name
  memory    = var.memory_mb
  vcpu      = var.vcpu
  cloudinit = libvirt_cloudinit_disk.init.id

  disk {
    volume_id = libvirt_volume.vm_disk.id
  }

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}

resource "terraform_data" "run_ansible_baseline" {
  triggers_replace = [
    libvirt_domain.vm.id,
    sha1(join("", [
      for f in fileset("${path.module}/../ansible/roles", "**/*.yml") :
      filesha1("${path.module}/../ansible/roles/${f}")
    ])),
  ]

  provisioner "local-exec" {
    working_dir = "${path.module}/../ansible"
    command     = <<-EOT
      ansible-playbook -i "${libvirt_domain.vm.network_interface[0].addresses[0]}," \
        -u ubuntu \
        --private-key ~/.ssh/libvirt_test \
        --skip-tags tailscale,lynis \
        playbook.yml
    EOT
  }
}

output "vm_ip" {
  value = libvirt_domain.vm.network_interface[0].addresses[0]
}
