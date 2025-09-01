# Terraform

Terraform is an open-source Infrastructure as Code (IaC) tool that allows you to
define, provision, and manage infrastructure resources across various cloud
providers and on-premises environments using a declarative configuration language.

We will be using it to provision our VMs as IaC way.

## Setup Terraform Files

This section guides you through preparing your Terraform configuration files for
your environment.

## Install Terraform CLI on Your Local Machine

Before running any Terraform commands, you need to install the Terraform CLI.
Follow the [HashiCorp Terraform installation guide](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
for your operating system.

## Spin Up Your First VM

1. Configure the Terraform files with your specific values.
2. Generate a password to be used in the [cloud-init file](../cloud-init/node1.yaml)
by running:

   ```bash
   mkpasswd --method=SHA-512
   ```

   Enter your desired password and copy the generated hash into the `passwd`
   field in your cloud-init file.
3. Initialize and apply your Terraform configuration:

   ```bash
   cd terraform/

   terraform init
   # Terraform has been successfully initialized!

   # Review your plan and check for any missing variables
   terraform plan -var-file="node.tfvars"

   # If everything looks correct, apply the configuration:
   terraform apply -var-file="node.tfvars"
   # ...
   # Enter a value: -> Yes
   # ...
   # Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
   ```

**Note**:
If you encounter the following error during `terraform apply`:

```text
the datastore "local" does not support content type "snippets"; supported
content types are: ...
```

SSH into your Proxmox VE host and add `snippets` to the local storage configuration:

```bash
sudo nano /etc/pve/storage.cfg

# Add 'snippets' to the content types if it's missing
dir: local
    path /var/lib/vz
    content iso,backup,vztmpl,snippets
```
