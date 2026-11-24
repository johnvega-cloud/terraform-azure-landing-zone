variable "prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  type = string
}

variable "allowed_locations" {
  type = list(string)
}

variable "required_tag_name" {
  type    = string
  default = "environment"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "create_management_groups" {
  type    = bool
  default = false
}

variable "subscription_id" {
  type    = string
  default = null
}
