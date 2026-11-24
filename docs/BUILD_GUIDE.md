# Build guide

The order in which this module is built, and why.

## 1. Inputs and validation (`modules/landing-zone/variables.tf`)

Start with what the module accepts. `environment` only allows `dev`, `stage` or `prod`, and
`address_space` must be a valid CIDR. Mistakes fail at `plan`, before anything reaches Azure.

## 2. Names and tags (`locals` in `main.tf`)

Every name is built from `<prefix>-<env>`. The required tag (`environment` by default) is always
merged into the tags, so the module's own resources pass the "require a tag" policy it creates.

## 3. Management group (optional)

Off by default. When on, it creates one management group per environment and moves the existing
subscription into it. It comes first in the file because it sits above everything else in Azure's
hierarchy: management group → subscription → resource group → resources.

## 4. Resource group

The container for everything else. Its ID is also the scope of the policy assignments.

## 5. VNet and subnets

One `/16` per environment. `cidrsubnet(address_space, 8, N)` turns it into `/24`s:
`N = 1` → app (`x.x.1.0/24`), `N = 2` → data (`x.x.2.0/24`).

## 6. NSGs and rules

One NSG per subnet, then the rules, then the subnet–NSG association.
Azure evaluates rules by priority, lowest number first. Its default rule 65000 allows all
VNet traffic, so the data NSG adds a deny at 4000. The allow from the app subnet (100) is
checked before that deny.

## 7. Azure Policy

Two built-in definitions are looked up by display name (`data "azurerm_policy_definition"`) and
assigned at resource group scope with their parameters. They come last because they need the
resource group ID.

## 8. Root configuration and environments

`main.tf` at the repo root calls the module once. `envs/*.tfvars` hold the per-environment values.
Each environment gets its own Terraform workspace, so its own state.

## 9. Tests

`tests/plan.tftest.hcl` mocks the azurerm provider. Two runs check names and subnet ranges, and two
call the module directly to check that its validations reject bad input.

## Provisioning order in Azure

Terraform works out the order from references:
resource group → VNet + NSGs + policy assignments (in parallel) → subnets → rules → subnet–NSG associations.
