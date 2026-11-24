locals {
  name = "${var.prefix}-${var.environment}"

  # The required tag is always set, so our own resources pass the policy.
  tags = merge(var.tags, {
    (var.required_tag_name) = var.environment
    managed-by              = "terraform"
  })

  # Two /24 subnets carved from the VNet range: app = x.x.1.0/24, data = x.x.2.0/24.
  subnets = {
    app  = cidrsubnet(var.address_space, 8, 1)
    data = cidrsubnet(var.address_space, 8, 2)
  }
}

# ---------- Management group (optional, needs tenant permissions) ----------

resource "azurerm_management_group" "this" {
  count        = var.create_management_groups ? 1 : 0
  name         = local.name
  display_name = "${local.name} landing zone"
}

resource "azurerm_management_group_subscription_association" "this" {
  count               = var.create_management_groups ? 1 : 0
  management_group_id = azurerm_management_group.this[0].id
  subscription_id     = "/subscriptions/${var.subscription_id}"
}

# ---------- Resource group ----------

resource "azurerm_resource_group" "this" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = local.tags
}

# ---------- Network ----------

resource "azurerm_virtual_network" "this" {
  name                = "${local.name}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "this" {
  for_each             = local.subnets
  name                 = "${local.name}-${each.key}-snet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value]
}

# ---------- NSGs: one per subnet ----------

resource "azurerm_network_security_group" "this" {
  for_each            = local.subnets
  name                = "${local.name}-${each.key}-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

# app subnet: HTTPS from the Internet.
resource "azurerm_network_security_rule" "app_https_in" {
  name                        = "allow-https-from-internet"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = local.subnets.app
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this["app"].name
}

# data subnet: only traffic coming from the app subnet.
resource "azurerm_network_security_rule" "data_from_app_in" {
  name                        = "allow-from-app-subnet"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = local.subnets.app
  destination_address_prefix  = local.subnets.data
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this["data"].name
}

# Azure's default rule 65000 allows all VNet-internal traffic; this deny
# (lower number = evaluated first) closes it so only the rule above applies.
resource "azurerm_network_security_rule" "data_deny_vnet_in" {
  name                        = "deny-other-vnet-traffic"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this["data"].name
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = local.subnets
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# ---------- Azure Policy (built-in definitions, assigned at RG scope) ----------

data "azurerm_policy_definition" "allowed_locations" {
  display_name = "Allowed locations"
}

data "azurerm_policy_definition" "require_tag" {
  display_name = "Require a tag on resources"
}

resource "azurerm_resource_group_policy_assignment" "allowed_locations" {
  name                 = "${local.name}-allowed-locations"
  resource_group_id    = azurerm_resource_group.this.id
  policy_definition_id = data.azurerm_policy_definition.allowed_locations.id

  parameters = jsonencode({
    listOfAllowedLocations = { value = var.allowed_locations }
  })
}

resource "azurerm_resource_group_policy_assignment" "require_tag" {
  name                 = "${local.name}-require-${var.required_tag_name}-tag"
  resource_group_id    = azurerm_resource_group.this.id
  policy_definition_id = data.azurerm_policy_definition.require_tag.id

  parameters = jsonencode({
    tagName = { value = var.required_tag_name }
  })
}
