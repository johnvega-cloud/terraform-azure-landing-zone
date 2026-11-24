output "resource_group_name" {
  value = module.landing_zone.resource_group_name
}

output "vnet_id" {
  value = module.landing_zone.vnet_id
}

output "subnet_ids" {
  value = module.landing_zone.subnet_ids
}

output "subnet_prefixes" {
  value = module.landing_zone.subnet_prefixes
}

output "nsg_ids" {
  value = module.landing_zone.nsg_ids
}

output "policy_assignment_ids" {
  value = module.landing_zone.policy_assignment_ids
}
