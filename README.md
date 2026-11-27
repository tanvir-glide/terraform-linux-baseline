# terraform-linux-baseline [WIP]

Terraform creates a test server in a Podman container, and then Ansible playbook
hardens the server.

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

- [x] Terraform starts an Ubuntu 22.04 container with systemd.
- [x] The container uses rootless Podman. It needs no cloud account.
- [x] The cgroup settings keep systemd running in the container.
- [x] The Ansible step is not done yet. See the TODO section.
---
- [ ] Setup Proxmox VE to have a more authentic terraform experience

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
- Target container: Ubuntu 22.04 with systemd

## Lessons learned
- **Default values cause drift:** Podman sets default values for `network_mode`, `pid_mode`, and `ulimit` blocks when a container starts. Terraform reads those values back and marks them as changes that force replacement.
- **Ignore runtime defaults:** Add `ignore_changes` in the `lifecycle` block for `network_mode`, `pid_mode`, and `ulimit` blocks. Avoid hardcoding `ulimit` numbers because host limits differ across machines.
- **Replacement triggers destroy bugs:** Forced container replacement can trigger a Podman destroy error and block `-replace` or apply steps. Fixing drift with `ignore_changes` stops needless container replacement.

## TODO

- [x] Add the Ansible repository as a Git submodule at `ansible/`.
- [x] Run the playbook in the container. Confirm that the run passes.
- [x] Check the result: SSH on port 2222, Fail2ban active, UFW default deny.
---
- [ ] Add a GitHub Actions check for `terraform fmt` and `terraform validate`.
- [ ] Add a screenshot of the verify commands.
- [ ] Use `for_each` to create a Debian, an Ubuntu, and a Rocky container.
- [ ] Add a `validation` block to one variable.
- [ ] Add a "Lessons learned" section.
---
- [ ] Add a second target for a cloud provider.
