variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test, or prod."
  }
}
variable "location" { default = "eastus2" }
variable "location_short" { default = "eus2" }
variable "suffix" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]{4,6}$", var.suffix))
    error_message = "Use a globally unique 4-6 character lowercase alphanumeric suffix."
  }
}
locals {
  prefix  = "mqgen-ai-${var.environment}-${var.location_short}"
  compact = "mqgenai${var.environment}${var.location_short}${var.suffix}"
  tags    = { org = "mqgen", owner = "mqgen-it", costcenter = "10999", project = "AI", environment = var.environment, managedby = "terraform" }
}
output "prefix" { value = local.prefix }
output "compact" { value = local.compact }
output "tags" { value = local.tags }
