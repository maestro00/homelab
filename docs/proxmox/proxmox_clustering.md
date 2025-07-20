# Creating Cluster From Proxmox VEs

## Copy SSH Keys Between the Nodes

Sync SSH Keys Between Nodes using ssh-copy-id

```bash
ssh-copy-id root@192.168.0.52
# Do the reverse too
ssh-copy-id root@192.168.0.51
```

## Create Cluster

Initialize a cluster named `lab-cluster`.

```bash
# Create cluster from the master node
pvecm create lab-cluster

# Add node to cluster from the other node
pvecm add 192.168.0.52
```

## Create NFS Shared Storage

We want shared storage available to both nodes (e.g., for ISO/images or VM
backups). Thus, we host the NFS share on one of the Proxmox nodes.

Create shared nfs folder in one of the node (I select the node which has bigger
disk)

```bash
mkdir -p /mnt/shared-nfs
chmod 777 /mnt/shared-nfs
```

Install NFS Server packages

```bash
apt update
apt install -y nfs-kernel-server
```

Then configure the exports file:

```bash
nano /etc/exports
# Add in the end of the file
/mnt/shared-nfs 192.168.0.0/24(rw,sync,no_subtree_check,no_root_squash)

# Apply the config:
exportfs -a
systemctl restart nfs-server
```

Now move to the other node and mount the shared storage from the first node.
To do that, first we need to install NFS Client.

```bash
apt install -y nfs-common
```

Then mount manually to test:

```bash
mkdir -p /mnt/shared-nfs
# (Use your first node's IP address)
mount 192.168.0.52:/mnt/shared-nfs /mnt/shared-nfs

# Test read/write:
touch /mnt/shared-nfs/test.txt

# If successful, make it permanent: (Use your first node's IP address)
echo "192.168.0.52:/mnt/shared-nfs /mnt/shared-nfs nfs defaults 0 0" >> /etc/fstab
```

Add NFS Shared Storage to Proxmox GUI

Now go to both Proxmox UI of cluster's master and:

```text
    Datacenter ➝ Storage ➝ Add ➝ NFS

    Fill in:
        ID: shared-nfs
        Server: 192.168.0.52
        Export: /mnt/shared-nfs
        Content: Choose ISO image, VZDump backup file, optionally Disk image
        Nodes: select both lab-pve1 and lab-pve2
```

After saving, verify under:

*Datacenter ➝ Storage ➝ shared-nfs*
it should show up under both nodes and be accessible.
