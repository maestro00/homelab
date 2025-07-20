# Prmoxmox VE Setup Guide

Promox is bla bla...

## Configurations in Proxmox

### Add pi-hole IP Address as DNS nameserver (To be reformatted)

According to our scheme, Raspberry pi4 *pi-hole* enabled DHCP Server and is our
dns-nameserver. Add it to network interface file under **iface**

```bash
nano /etc/network/interfaces
...
    dns-nameservers 192.168.0.10
# restart networking service to apply the change
systemctl restart networking.service
```

### Set Locale settings

Set Locale settings before going forward for attaching Image.

I use Finnish locale. Replace locale abbrevations as your desire.

```bash
nano /etc/locale.gen
# fi_FI.UTF-8 UTF-8 # Uncomment this line, save and exit.

# Regenerate the locale
locale-gen
# Generating locales (this might take a while)...
#   en_US.UTF-8... done
#   fi_FI.UTF-8... done
# Generation complete.

update-locale LANG=fi_FI.UTF-8 # Optional, set your locale to your language
```

Verify locale setting is working

```bash
locale -a # You should see your locale in the output
```

## Proxmox Cloud Image Attachment

We need to create a cloud-init enabled Proxmox template first. This is a
one-time manual setup per OS version.

<!-- markdownlint-disable MD013 -->
```bash
# Choose desired image version instead of jammy
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O ubuntu-22.04-cloud.img
```
<!-- markdownlint-enable MD013 -->

Import image into Proxmox

```bash
qm create 9000 --name ubuntu-22.04-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 ubuntu-22.04-cloud.img shared-nfs
# unused0: successfully imported disk 'shared-nfs:9000/vm-9000-disk-0.raw'
qm set 9000 --scsihw virtio-scsi-pci --scsi0 shared-nfs:9000/vm-9000-disk-0.raw
qm set 9000 --ide2 shared-nfs:cloudinit
# successfully created disk 'shared-nfs:9000/vm-9000-cloudinit.qcow2,media=cdrom'
qm set 9000 --boot order=scsi0 --bootdisk scsi0 --serial0 socket --vga serial0

# Clone from any node
qm clone 9000 170 --name k8s-node-1 --full true --target lab-pve2
```

Now you can refer the image in your terraform template as **ubuntu-22.04-template**.
