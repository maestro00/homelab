# Terraform conventions

Read the current `terraform/` and `lxc/` files before applying these rules.
Repository code and provider versions are canonical.

## Code style

- Declare variables with `type` and `description`; add defaults only when
  useful and mark secrets `sensitive = true`.
- Pass values through tfvars rather than hardcoding them in resources.
- Use `list(object({...}))` for repeated inputs, then convert to a map:

```hcl
for_each = { for item in var.items : item.name => item }
```

- Reference fields with `each.value.<field>` and use `snake_case` for
  variables and resources.
- Follow the VM name and ID conventions already present in tfvars. Do not
  assume a template or datastore without checking the target PVE host.

## Cloud-init and storage

- Keep cloud-init templates under `terraform/cloud-init/` unless the current
  repository has established a different location.
- Render templates with `templatefile()` and upload snippets to a
  directory-capable datastore.
- Preserve standard users, packages, sudo, and node-specific settings from
  existing templates.
- Confirm shared storage is mounted on every required PVE host before a
  plan or apply.

## Teaching and change workflow

1. Explain the Proxmox concept and why the resource is needed.
2. Read the provider reference only for the resource types being changed.
3. Show an annotated resource and its matching tfvars input.
4. Explain relationships, dependencies, and manual Proxmox steps.
5. Run `terraform fmt` and `terraform validate`, then review the plan.

For K3s nodes, retain an odd control-plane count and exclude the manually
provisioned Pi from Terraform automation.
