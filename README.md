# terraform-linux-baseline [WIP]

Two Terraform targets that create a test server and then run the
[ansible-linux-baseline](https://github.com/tanvir-glide/ansible-linux-baseline)
playbook against it:

- **`libvirt/`** — an Ubuntu 24.04 cloud image booted as a KVM VM via
  cloud-init, then hardened over SSH. This is the "authentic" target: a real
  machine with a real SSH port change
- **`podman/`** — an Ubuntu 22.04 container with systemd, using rootless
  Podman

Both targets share the same `ansible/` submodule, so the hardening logic lives
in one place.

## Table of Contents

- [Goal](#goal)
- [Status](#status)
- [Requirements](#requirements)
- [Usage](#usage)
- [Tested on](#tested-on)
- [TODO](#todo)

## Goal

One `terraform apply` creates a container and runs the [ansible-linux-baseline](https://github.com/tanvir-glide/ansible-linux-baseline) playbook in it.

## Status

### libvirt target

- [x] Terraform imports an Ubuntu 24.04 (Noble) cloud image as a base volume.
- [x] A qcow2 overlay disk is created from the base image, so the 593 MB
      download is shared and never written to.
- [x] cloud-init injects an SSH key and creates the `ubuntu` user on first
      boot.
- [x] The Ansible baseline runs over SSH from a `terraform_data` provisioner.
- [x] Verified: UFW active, fail2ban active, SSH on port 2222, zram active,
      `swap.img` removed.

### Podman target

- [x] Terraform starts an Ubuntu 22.04 container with systemd.
- [x] The container uses rootless Podman. It needs no cloud account.
- [x] The cgroup settings keep systemd running in the container.
- [x] The Ansible baseline runs against the container via
      `containers.podman.podman`.

## Requirements

- A Linux machine with rootless Podman
- Terraform 1.4 or later

Start the Podman socket. Terraform uses it to talk to Podman.

```bash
systemctl --user enable --now podman.socket
```

## Usage

```bash
git clone https://github.com/Tanvir101cmd/terraform-linux-baseline.git
cd terraform-linux-baseline
terraform init
terraform apply
```

Check the container. `running` or `degraded` is a pass.

```bash
podman exec test_server systemctl is-system-running
```

Delete the container:

```bash
terraform destroy
```

The default socket path is for user ID 1000. For another user ID, run `terraform apply -var "podman_socket=unix:///run/user/$(id -u)/podman/podman.sock"`.

## Tested on

- Host OS: Debian Linux with rootless Podman
- Target container: [Ubuntu 24.04](https://cloud-images.ubuntu.com/noble/20261017/noble-server-cloudimg-amd64.img)

## Lessons learned
- **Default values cause drift:** Podman sets default values for `network_mode`, `pid_mode`, and `ulimit` blocks when a container starts. Terraform reads those values back and marks them as changes that force replacement.
- **Ignore runtime defaults:** Add `ignore_changes` in the `lifecycle` block for `network_mode`, `pid_mode`, and `ulimit` blocks. Avoid hardcoding `ulimit` numbers because host limits differ across machines.
- **Replacement triggers destroy bugs:** Forced container replacement can trigger a Podman destroy error and block `-replace` or apply steps. Fixing drift with `ignore_changes` stops needless container replacement.

## TODO

- [x] Add the Ansible repository as a Git submodule at `ansible/`.
- [x] Run the playbook in the container. Confirm that the run passes.
- [x] Check the result: SSH on port 2222, Fail2ban active, UFW default deny.
---
- [x] Add a GitHub Actions check for `terraform fmt` and `terraform validate`.
- [ ] Add a screenshot of the verify commands.
- [ ] Use `for_each` to create a Debian, an Ubuntu, and a Rocky container.
- [ ] Add a `validation` block to one variable.
- [x] Add a "Lessons learned" section.
---
- [ ] Add a second target for a cloud provider.
