# Proxmox VE Setup Guide

Proxmox Virtual Environment (Proxmox VE) is an open-source server virtualization
platform that allows you to manage virtual machines, containers, storage, and
networking in a unified web interface.

This guide provides step-by-step instructions for configuring Proxmox VE,
including network settings, locale configuration, and creating a cloud-init
enabled template for automated VM provisioning.

## Configurations in Proxmox

### Set Locale Settings

Set the system locale before proceeding with image attachment. This example uses
the Finnish locale; replace with your preferred locale as needed.

```bash
nano /etc/locale.gen
# Uncomment your desired locale, e.g.:
# fi_FI.UTF-8 UTF-8

# Regenerate the locale
locale-gen
# Output should confirm generation of selected locales

# Optionally, set your locale as default
update-locale LANG=fi_FI.UTF-8
```

Verify that the locale is set correctly:

```bash
locale -a # Your selected locale should appear in the output
```

## Proxmox Cloud Image Attachment

To automate VM provisioning, you need to create a cloud-init enabled Proxmox
template. This is a one-time manual setup per OS version.

<!-- markdownlint-disable MD013 -->
```bash
# Download the desired Ubuntu cloud image (replace 'jammy' with your preferred version)
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O ubuntu-22.04-cloud.img
```
<!-- markdownlint-enable MD013 -->

Import the image into Proxmox:

```bash
qm create 9000 --name ubuntu-22.04-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 ubuntu-22.04-cloud.img shared-nfs
# Output: unused0: successfully imported disk 'shared-nfs:9000/vm-9000-disk-0.raw'
qm set 9000 --scsihw virtio-scsi-pci --scsi0 shared-nfs:9000/vm-9000-disk-0.raw
qm set 9000 --ide2 shared-nfs:cloudinit
# Output: successfully created disk 'shared-nfs:9000/vm-9000-cloudinit.qcow2,media=cdrom'
qm set 9000 --boot order=scsi0 --bootdisk scsi0 --serial0 socket --vga serial0

# Clone the template from any node
qm clone 9000 170 --name k8s-node-1 --full true --target lab-pve2
```

You can now reference the template in your Terraform configuration as **ubuntu-22.04-template**.
