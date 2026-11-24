# Tests with a mocked provider: no Azure login, nothing real is created.
# "apply" here only applies against the mock, so computed IDs get fake values.

mock_provider "azurerm" {
  mock_data "azurerm_policy_definition" {
    defaults = {
      id = "/providers/Microsoft.Authorization/policyDefinitions/mock"
    }
  }

  # Fake IDs in valid Azure format, so resources that take an ID as input accept them.
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg"
    }
  }

  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-snet"
    }
  }

  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/networkSecurityGroups/mock-nsg"
    }
  }
}

variables {
  prefix            = "azlz"
  environment       = "dev"
  location          = "eastus"
  address_space     = "10.10.0.0/16"
  allowed_locations = ["eastus"]
}

run "dev_builds_expected_names_and_ranges" {
  command = apply

  assert {
    condition     = module.landing_zone.resource_group_name == "azlz-dev-rg"
    error_message = "resource group name should be <prefix>-<env>-rg"
  }

  assert {
    condition     = module.landing_zone.subnet_prefixes.app == "10.10.1.0/24" && module.landing_zone.subnet_prefixes.data == "10.10.2.0/24"
    error_message = "subnets should be x.x.1.0/24 (app) and x.x.2.0/24 (data)"
  }

  assert {
    condition     = length(module.landing_zone.subnet_ids) == 2
    error_message = "two subnets (app, data) should be planned"
  }

  assert {
    condition     = length(module.landing_zone.policy_assignment_ids) == 2
    error_message = "two policy assignments should be planned"
  }

  assert {
    condition     = module.landing_zone.management_group_id == null
    error_message = "management groups are off by default"
  }
}

run "prod_uses_its_own_range" {
  command = plan

  variables {
    environment   = "prod"
    address_space = "10.30.0.0/16"
  }

  assert {
    condition     = module.landing_zone.resource_group_name == "azlz-prod-rg"
    error_message = "prod resource group name is wrong"
  }

  assert {
    condition     = module.landing_zone.subnet_prefixes.app == "10.30.1.0/24"
    error_message = "prod app subnet should come from the prod range"
  }
}

# The validation lives in the module, so these two runs call the module directly.
run "rejects_unknown_environment" {
  command = plan

  module {
    source = "./modules/landing-zone"
  }

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "management_group_needs_subscription_id" {
  command = plan

  module {
    source = "./modules/landing-zone"
  }

  variables {
    create_management_groups = true
  }

  expect_failures = [var.subscription_id]
}
