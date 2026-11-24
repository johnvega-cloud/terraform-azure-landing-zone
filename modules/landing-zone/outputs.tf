output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "subnet_ids" {
  description = "Map of subnet name (app, data) to subnet ID."
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "subnet_prefixes" {
  description = "Map of subnet name (app, data) to CIDR."
  value       = local.subnets
}

output "nsg_ids" {
  description = "Map of subnet name (app, data) to NSG ID."
  value       = { for k, n in azurerm_network_security_group.this : k => n.id }
}

output "policy_assignment_ids" {
  value = [
    azurerm_resource_group_policy_assignment.allowed_locations.id,
    azurerm_resource_group_policy_assignment.require_tag.id,
  ]
}

output "management_group_id" {
  value = var.create_management_groups ? azurerm_management_group.this[0].id : null
}
