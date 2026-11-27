# terraform-linux-baseline

Two Terraform targets that create a test server and then run the
[ansible-linux-baseline](https://github.com/tanvir-glide/ansible-linux-baseline)
playbook against it:

- **`libvirt/`** - an Ubuntu 24.04 cloud image booted as a KVM VM via
  cloud-init, then hardened over SSH. This is the "authentic" target: a real
  machine with a real SSH port change
- **`podman/`** - an Ubuntu 22.04 container with systemd, using rootless
  Podman

Both targets share the same `ansible/` submodule, so the hardening logic lives
in one place.

## Table of Contents

- [Goal](#goal)
- [Status](#status)
- [Requirements](#requirements)
- [Usage](#usage)
  - [Libvirt](#libvirt)
  - [Podman](#podman)
- [Tested on](#tested-on)
- [Design Decisions](#design-decisions)
- [Lessons learned](#lessons-learned)
- [TODO](#todo)

## Goal

One `terraform apply` creates a server, either a libvirt/KVM VM or a rootless Podman
container - and runs the [ansible-linux-baseline](https://github.com/tanvir-glide/ansible-linux-baseline) playbook in it.

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

### Common

* A Linux host
* Terraform 1.4 or later
* The `ansible-linux-baseline` repository checked out as the `ansible/` submodule:
  ```bash
  git submodule update --init --recursive
  ```
* `ansible-playbook` installed on the host (the provisioner runs it locally, not inside the target).

### libvirt target

* KVM/QEMU and libvirt installed, with your user in the `libvirt` group:
  ```bash
  sudo usermod -aG libvirt "$USER"
  # log out and back in
  ```
* A storage pool named `default`, active and auto-started:
  ```bash
  virsh pool-list --all
  # if it is missing:
  sudo virsh pool-define-as default dir --target /var/lib/libvirt/images
  sudo virsh pool-build default
  sudo virsh pool-start default
  sudo virsh pool-autostart default
  ```
* An SSH keypair. The public key goes into `libvirt/user-data.yaml` so cloud-init can install it into the `ubuntu` account:
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/libvirt_test -N ""
  cat ~/.ssh/libvirt_test.pub   # paste into libvirt/user-data.yaml
  ```
* The Ubuntu Noble cloud image downloaded and placed at `libvirt/noble-server-cloudimg-amd64.img` (from https://cloud-images.ubuntu.com/noble/current/). The image is gitignored - it is 593 MB and should not live in the repository.

### podman target

* Rootless Podman with the user socket enabled:
  ```bash
  systemctl --user enable --now podman.socket
  ```

## Usage

```bash
git clone --recurse-submodules https://github.com/tanvir-glide/terraform-linux-baseline.git
cd terraform-linux-baseline
```

### libvirt

```bash
cd libvirt
terraform init
terraform apply
```

The first apply imports the base image, creates the overlay disk and cloud-init ISO, boots the VM, and runs the Ansible baseline over SSH. When it finishes it prints the VM IP:

```text
vm_ip = "192.168.122.247"
```

Check the result. `running` or `degraded` is a pass for `is-system-running`:

```bash
VM_IP=$(terraform output -raw vm_ip)
ssh -p 2222 -i ~/.ssh/libvirt_test "ubuntu@${VM_IP}" '
  systemctl is-system-running;
  echo "--- UFW ---";
  sudo ufw status | head -5;
  echo "--- fail2ban ---";
  systemctl is-active fail2ban'
```

Expected: `degraded` (or `running`), `Status: active` for UFW, and `active` for fail2ban.

> **Note the port:** the baseline moves SSH to `2222`, so `ssh` without `-p 2222` times out once the playbook has run.

Delete the VM and its volumes:

```bash
terraform destroy
```

### podman

```bash
cd podman
terraform init
terraform apply
```

Check the container. `running` or `degraded` is a pass:

```bash
podman exec test_server systemctl is-system-running
```

Delete the container:

```bash
terraform destroy
```

> The default socket path is for user ID `1000`. For another user ID, run `terraform apply -var "podman_socket=unix:///run/user/$(id -u)/podman/podman.sock"`.

## Tested on

- Host OS: Debian Linux with rootless Podman
- libvirt target: Ubuntu 24.04 daily cloud image, KVM on an i3-6100U with 8 GB RAM
- podman target: Ubuntu 22.04 container with systemd, rootless Podman

## Design decisions

- **Base image vs. overlay disk**: the downloaded image is never written to.
  Each VM gets a QCOW2 overlay, so the 593 MB base is shared and a second VM
  costs a few MB
- **`terraform_data` over `null_resource`**: `terraform_data` is built into
  Terraform 1.4+, has no provider dependency, and its `triggers_replace` is
  explicit
- **`validate` in CI, not `apply`**: nested virtualization on GitHub-hosted
  runners is experimental. The full apply is verified locally; CI guards
  syntax and provider config
- **Molecule deferred to the submodule**: the Ansible role's CI lives in
  `ansible-linux-baseline`. Duplicating it here adds no coverage

## Lessons learned

### libvirt
- **The base image and the VM disk are two different files.** Booting the
  downloaded `.img` directly would write into the 593 MB file and make it
  unusable for the next VM. The overlay (`base_volume_id` + a separate
  `libvirt_volume`) keeps the base pristine and starts the VM disk at a few
  MB.

- **Permission denied on the base image is not (only) a Unix permissions
  problem.** Ubuntu's libvirt AppArmor profile restricts which paths the QEMU
  process can open. Fixing `chown` on the file is necessary but not
  sufficient; the local AppArmor abstraction needs an `rwk` rule for the image
  path, e.g. in `/etc/apparmor.d/local/abstractions/libvirt-qemu`:
  ``` bash
  /var/lib/libvirt/images/** rwk,
  ```
  Then do `sudo systemctl reload apparmor && sudo systemctl restart libvirtd`

- **Failed to lock byte 100 is the same AppArmor issue, one permission
  bit later.** QEMU locks its disk files; the `k` in `rwk` is what allows the
  lock. A rule with only `r` gets past the first error and fails on the second.

- **A failed apply can leave a defined-but-not-created domain behind.**
  If `terraform apply` dies after `libvirt_domain.vm` starts being created,
  the next run may fail with `domain already exists`. `virsh undefine <name>`
  clears it; a `terraform import` is the alternative but is more work for a
  throwaway test VM.

- **`systemctl is-system-running` exits non-zero on `degraded`.** Chaining it
  with `&&` to other checks silently skips them. Use `;` when the check is
  "either `running` or `degraded` counts as a pass".

### podman
- **Default values cause drift:** Podman sets default values for `network_mode`, `pid_mode`, and `ulimit` blocks when a container starts. Terraform reads those values back and marks them as changes that force replacement.
- **Ignore runtime defaults:** Add `ignore_changes` in the `lifecycle` block for `network_mode`, `pid_mode`, and `ulimit` blocks. Avoid hardcoding `ulimit` numbers because host limits differ across machines.
- **Replacement triggers destroy bugs:** Forced container replacement can trigger a Podman destroy error and block `-replace` or apply steps. Fixing drift with `ignore_changes` stops needless container replacement.

## TODO

### libvirt
- [ ] Pin the cloud image to a stable release instead of a daily build, or document the daily URL explicitly
- [ ] Ship `user-data.yaml.example` and gitignore the real `user-data.yaml` so personal SSH keys stay out of git
- [ ] Use `for_each` to create Debian, Ubuntu, and Rocky VMs from their respective cloud images. The Ansible role already has `debian.yml` and `redhat.yml` vars
- [ ] Add a `validation` block to `disk_bytes` (minimum 5 GiB) and `memory_mb` (minimum 1024).

### podman
- [ ] Use `for_each` to create a Debian, an Ubuntu, and a Rocky container
- [ ] Add a `validation` block to one variable

### Repo-wide
- [ ] Add a screenshot (or a text transcript) of the verify commands to the README
- [ ] Wire the `ansible/` Molecule scenarios into CI so a role change fails the build, not just `terraform validate`
- [ ] Add `pre-commit` hooks: `terraform fmt`, `tflint`, `ansible-lint`, `yamllint`, `gitleaks`
- [ ] Add a second target for a cloud provider (Hetzner, DigitalOcean), reusing the same `../ansible` playbook
