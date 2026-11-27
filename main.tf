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

  cgroupns_mode = "host"

  volumes {
    host_path      = "/sys/fs/cgroup"
    container_path = "/sys/fs/cgroup"
  }
}
