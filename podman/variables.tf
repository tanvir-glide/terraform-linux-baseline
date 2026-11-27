variable "container_name" {
  type    = string
  default = "test_server"
}

variable "podman_socket" {
  type    = string
  default = "unix:///run/user/1000/podman/podman.sock"
}
