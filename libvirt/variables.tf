variable "vm_name" {
  type    = string
  default = "test_server"
}

variable "pool" {
  type    = string
  default = "default"
}

variable "base_image" {
  type    = string
  default = "noble-server-cloudimg-amd64.img"
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "vcpu" {
  type    = number
  default = 2
}

variable "disk_bytes" {
  type    = number
  default = 8 * 1024 * 1024 * 1024
}
