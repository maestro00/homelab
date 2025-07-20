# Terraform

Terraform is bla bla...

## Setup Terraform Files

## Install Terraform CLI on your local machine

Before running any Terraform commands, we need to install Terraform CLI package.
Follow [Hashicorp Terraform Readme](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

## Spin Up Your First VM

1. Configure the terraform files according your values.
2. Generate password to be used in [cloud-init file](../cloud-init/node1.yaml)
by `mkpasswd --method=SHA-512`, enter your very secret password and copy the
encrypted key into `passwd` field.
3. Run following for initializing and running VM.

```bash
cd terraform/

terraform init
# Terraform has been successfully initialized!

# Confirm your plan and see if any missing variables
terraform plan -var-file="node1.tfvars"

# Then, if all looks good:
terraform apply -var-file="node1.tfvars"
...
# Enter a value: -> Yes
...
# Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

**Note**: If you face with error

```text
the datastore "local" does not support content type "snippets"; supported
content types are: ...
```

during `terraform apply` command, ssh to your PVE and add snippets to local
storage section.

```bash
sudo nano /etc/pve/storage.cfg

# Add snippets if it's missing
dir: local
    path /var/lib/vz
    content iso,backup,vztmpl,snippets
```
