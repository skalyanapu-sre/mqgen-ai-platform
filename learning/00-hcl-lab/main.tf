# This root has no cloud provider, no backend and no Azure resources.
terraform {
  required_version = ">= 1.13.5, < 2.0"
}
variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test, or prod."
  }
}
variable "suffix" {
  type    = string
  default = "x7k92"
}
module "naming" {
  source      = "../../modules/naming"
  environment = var.environment
  suffix      = var.suffix
}
locals {
  data_cidr = "10.41.0.0/16"
  subnets = {
    host      = cidrsubnet(local.data_cidr, 8, 0)
    container = cidrsubnet(local.data_cidr, 8, 1)
    endpoints = cidrsubnet(local.data_cidr, 8, 2)
  }
  usable_addresses_per_24 = pow(2, 32 - 24) - 5
  schema_names            = toset(["bronze", "silver", "gold"])
  schema_plan             = { for layer in local.schema_names : layer => "mqgen_ai_${var.environment}.${layer}" }
}
output "prefix" { value = module.naming.prefix }
output "tags" { value = module.naming.tags }
output "subnets" { value = local.subnets }
output "usable_addresses" { value = local.usable_addresses_per_24 }
output "schemas" { value = local.schema_plan }
