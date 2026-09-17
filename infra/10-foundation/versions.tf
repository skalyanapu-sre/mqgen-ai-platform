terraform {
  required_version = ">= 1.13.5, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
  backend "azurerm" {}
}
provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}
variable "subscription_id" { type = string }
variable "environment" { default = "dev" }
variable "location" { default = "eastus2" }
variable "location_short" { default = "eus2" }
variable "suffix" { type = string }
module "naming" {
  source         = "../../modules/naming"
  environment    = var.environment
  location       = var.location
  location_short = var.location_short
  suffix         = var.suffix
}
locals {
  prefix = module.naming.prefix
  tags   = module.naming.tags
}
data "azurerm_client_config" "current" {}
