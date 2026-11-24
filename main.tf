module "landing_zone" {
  source = "./modules/landing-zone"

  prefix                   = var.prefix
  environment              = var.environment
  location                 = var.location
  address_space            = var.address_space
  allowed_locations        = var.allowed_locations
  required_tag_name        = var.required_tag_name
  tags                     = var.tags
  create_management_groups = var.create_management_groups
  subscription_id          = var.subscription_id
}
