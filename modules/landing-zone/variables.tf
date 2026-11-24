variable "prefix" {
  description = "Short name prefix for every resource (lowercase letters and digits)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.prefix))
    error_message = "prefix must be 2-10 lowercase letters or digits."
  }
}

variable "environment" {
  description = "Environment name: dev, stage or prod."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "location" {
  description = "Azure region for the resource group and network."
  type        = string
}

variable "address_space" {
  description = "VNet CIDR, e.g. 10.10.0.0/16. Use a different range per environment."
  type        = string

  validation {
    condition     = can(cidrhost(var.address_space, 0))
    error_message = "address_space must be a valid CIDR."
  }
}

variable "allowed_locations" {
  description = "Regions allowed by the 'Allowed locations' policy."
  type        = list(string)
}

variable "required_tag_name" {
  description = "Tag that every resource in the resource group must have."
  type        = string
  default     = "environment"
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}

variable "create_management_groups" {
  description = "Create a management group for this environment and move the subscription into it. Needs tenant-level permissions."
  type        = bool
  default     = false
}

variable "subscription_id" {
  description = "Existing subscription that hosts the landing zone. Only used when create_management_groups = true."
  type        = string
  default     = null

  validation {
    condition     = !var.create_management_groups || var.subscription_id != null
    error_message = "subscription_id is required when create_management_groups = true."
  }
}
