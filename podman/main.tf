terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.2"
    }
  }
}

provider "docker" {
  host = var.podman_socket
}

resource "docker_image" "ubuntu_systemd" {
  # shortcut: tag is latest, pin a version when the build must repeat exactly
  name         = "docker.io/geerlingguy/docker-ubuntu2204-ansible:latest"
  keep_locally = true
}

resource "docker_container" "test_server" {
  name       = var.container_name
  image      = docker_image.ubuntu_systemd.image_id
  privileged = true # systemd needs it in a container, test use only
  command    = ["/lib/systemd/systemd"]

  # systemd stops at once in a rootless container without these two settings
  cgroupns_mode = "host"

  volumes {
    host_path      = "/sys/fs/cgroup"
    container_path = "/sys/fs/cgroup"
  }

  # Podman fills in these values. Without this block, every plan replaces the container.
  lifecycle {
    ignore_changes = [network_mode, pid_mode, ulimit]
  }
}

resource "terraform_data" "run_ansible_baseline" {
  # shortcut: playbook.yml is not hashed, use -replace when only it changes
  triggers_replace = [
    docker_container.test_server.id,
    sha1(join("", [
      for f in fileset("${path.module}/../ansible/roles", "**/*.yml") :
      filesha1("${path.module}/ansible/roles/${f}")
    ])),
  ]

  provisioner "local-exec" {
    working_dir = "${path.module}/../ansible"
    command     = <<-EOT
      podman exec ${var.container_name} systemctl is-system-running --wait || true
      ansible-playbook -i "${var.container_name}," \
        -c containers.podman.podman \
        --skip-tags tailscale,lynis \
        playbook.yml
    EOT
  }
}
