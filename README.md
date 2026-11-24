# terraform-azure-landing-zone

A small, reusable Terraform module that lays down the base of an Azure environment:
resource group, VNet, subnets, NSGs and Azure Policy assignments, with the same code
for **dev**, **stage** and **prod**.

![architecture](docs/architecture.svg)

## Problem

> Create a Terraform module that provisions an enterprise Azure landing zone with Management
> Groups, subscriptions, resource groups, VNets, subnets, NSGs, and Azure Policy assignments.
> Support dev, stage, and production environments through parameterized configurations.

## What it builds (per environment)

| Piece | Name | Details |
|---|---|---|
| Resource group | `<prefix>-<env>-rg` | Every resource gets the tags `environment=<env>` and `managed-by=terraform` |
| VNet | `<prefix>-<env>-vnet` | One `/16` per environment |
| Subnets | `<prefix>-<env>-app-snet`, `-data-snet` | `x.x.1.0/24` and `x.x.2.0/24`, carved with `cidrsubnet` |
| NSGs | `<prefix>-<env>-app-nsg`, `-data-nsg` | app: HTTPS from Internet. data: only from the app subnet (an explicit deny at 4000 closes Azure's default allow-VNet rule) |
| Policy | `Allowed locations`, `Require a tag on resources` | Built-in definitions, assigned at **resource group** scope |
| Management group | `<prefix>-<env>` | Optional (`create_management_groups = true`), moves the subscription into it |

## Design decisions

- **Subscriptions are an input, not a resource.** Creating subscriptions needs an EA/MCA billing
  account. In practice a landing zone receives subscriptions that already exist (subscription vending
  is a separate process).
- **Policies are assigned to the resource group, not the subscription,** so the module is safe to run
  in a shared subscription without affecting other teams.
- **Management groups are off by default** because they need tenant-level permissions.
- **One Terraform workspace per environment.** All three tfvars files use the same code but
  different state, so applying prod never touches dev.

## Prerequisites

- Terraform >= 1.7 (tested with 1.14.7) and Azure CLI, logged in with `az login`
- Owner (or Contributor + Resource Policy Contributor) on the target subscription
- For management groups: Management Group Contributor at the tenant root

## Usage

```bash
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init
terraform workspace new dev        # once per environment
terraform workspace select dev
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
terraform destroy -var-file=envs/dev.tfvars
```

Using the module from another configuration:

```hcl
module "landing_zone" {
  source = "github.com/<owner>/terraform-azure-landing-zone//modules/landing-zone"

  prefix            = "azlz"
  environment       = "stage"
  location          = "eastus"
  address_space     = "10.20.0.0/16"
  allowed_locations = ["eastus"]
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `prefix` | string | — | 2–10 lowercase letters/digits |
| `environment` | string | — | `dev`, `stage` or `prod` (validated) |
| `location` | string | — | Azure region |
| `address_space` | string | — | VNet CIDR (validated) |
| `allowed_locations` | list(string) | — | Regions allowed by policy |
| `required_tag_name` | string | `environment` | Tag every resource must carry |
| `tags` | map(string) | `{}` | Extra tags |
| `create_management_groups` | bool | `false` | Create a management group and move the subscription |
| `subscription_id` | string | `null` | Required only when `create_management_groups = true` |

Outputs: `resource_group_name`, `vnet_id`, `subnet_ids`, `subnet_prefixes`, `nsg_ids`,
`policy_assignment_ids`, `management_group_id`.

## Tests and CI

`terraform test` runs 4 tests against a **mocked** provider (no Azure login, nothing created):
names and subnet ranges for dev and prod, rejection of an unknown environment, and the
`subscription_id` requirement for management groups. CI (`.github/workflows/ci.yml`) runs
`fmt -check`, `validate` and `test`.

## Tested in real Azure

- `apply` of **dev**: 13 resources, checked with `az` (subnets, NSG association, rules, policy parameters).
- A second `plan` shows no changes (idempotent).
- Policy enforcement: an NSG **without** the `environment` tag and an NSG in **westus** were both
  rejected with `RequestDisallowedByPolicy`. A tagged NSG in eastus was accepted (then deleted).
- `destroy`: 13 destroyed, resource group gone.
- **stage** and **prod**: `plan` only (13 to add each, correct ranges and names) in their own workspaces.
- **Not tested:** management groups (no tenant-level permissions in the test account).

## Security and idempotency notes

- No subscription IDs or secrets are committed; the provider reads `ARM_SUBSCRIPTION_ID` or the az login.
- The data subnet is closed to everything except the app subnet, including other VNet traffic.
- The policies use `Deny` (the built-in default effect), so a non-compliant resource is never created.
- Policy assignments can take a few minutes to become effective after the first apply.
- Re-running `apply` with the same inputs makes no changes.
- State is local in this lab. In a team setup, use a remote backend (Azure Storage with locking).
