terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The subscription comes from the ARM_SUBSCRIPTION_ID environment variable
# (or the az CLI login), so no IDs are committed to the repo.
provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
}
