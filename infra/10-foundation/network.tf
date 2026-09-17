variable "enable_vpn" { default = true }
variable "state_account_id" { type = string }
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.prefix}-platform"
  location = var.location
  tags     = local.tags
}
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-${local.prefix}-hub"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  address_space       = ["10.40.0.0/16"]
  tags                = local.tags
}
resource "azurerm_virtual_network" "data" {
  name                = "vnet-${local.prefix}-data"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  address_space       = ["10.41.0.0/16"]
  tags                = local.tags
}
locals {
  hub_subnets = {
    gateway   = { name = "GatewaySubnet", cidr = "10.40.0.0/27" }
    endpoints = { name = "snet-${local.prefix}-hub-pe", cidr = "10.40.1.0/24" }
    runner    = { name = "snet-${local.prefix}-runner", cidr = "10.40.2.0/24" }
  }
}
resource "azurerm_subnet" "hub" {
  for_each             = local.hub_subnets
  name                 = each.value.name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [each.value.cidr]
}
resource "azurerm_subnet" "dns" {
  name                 = "snet-${local.prefix}-dns-in"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.40.3.0/28"]
  delegation {
    name = "dns-resolver"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
resource "azurerm_private_dns_resolver" "main" {
  name                = "dnspr-${local.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  virtual_network_id  = azurerm_virtual_network.hub.id
  tags                = local.tags
}
resource "azurerm_private_dns_resolver_inbound_endpoint" "main" {
  name                    = "dnsin-${local.prefix}"
  private_dns_resolver_id = azurerm_private_dns_resolver.main.id
  location                = var.location
  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.dns.id
  }
  tags = local.tags
}
resource "azurerm_public_ip" "vpn" {
  count               = var.enable_vpn ? 1 : 0
  name                = "pip-${local.prefix}-vpn"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.tags
}
resource "azurerm_virtual_network_gateway" "vpn" {
  count               = var.enable_vpn ? 1 : 0
  name                = "vgw-${local.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = false
  bgp_enabled         = false
  sku                 = "VpnGw1AZ"
  ip_configuration {
    name                          = "gateway"
    public_ip_address_id          = azurerm_public_ip.vpn[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.hub["gateway"].id
  }
  vpn_client_configuration {
    address_space        = ["172.30.240.0/24"]
    vpn_client_protocols = ["OpenVPN"]
    vpn_auth_types       = ["AAD"]
    aad_tenant           = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}"
    aad_audience         = "c632b3df-fb67-4d84-bdcf-b95ad541b5c8"
    aad_issuer           = "https://sts.windows.net/${data.azurerm_client_config.current.tenant_id}/"
  }
  tags = local.tags
}
resource "azurerm_virtual_network_peering" "hub_data" {
  name                      = "hub-to-data"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.data.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = var.enable_vpn
  depends_on                = [azurerm_virtual_network_gateway.vpn]
}
resource "azurerm_virtual_network_peering" "data_hub" {
  name                      = "data-to-hub"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.data.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_forwarded_traffic   = true
  use_remote_gateways       = var.enable_vpn
  depends_on                = [azurerm_virtual_network_gateway.vpn, azurerm_virtual_network_peering.hub_data]
}
locals {
  db_subnets = {
    host          = { cidr = "10.41.0.0/24", vnet = azurerm_virtual_network.data.name, nsg = "workload" }
    container     = { cidr = "10.41.1.0/24", vnet = azurerm_virtual_network.data.name, nsg = "workload" }
    authhost      = { cidr = "10.40.4.0/26", vnet = azurerm_virtual_network.hub.name, nsg = "auth" }
    authcontainer = { cidr = "10.40.4.64/26", vnet = azurerm_virtual_network.hub.name, nsg = "auth" }
  }
}
resource "azurerm_network_security_group" "db" {
  for_each            = toset(["workload", "auth"])
  name                = "nsg-${local.prefix}-db-${each.key}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
}
resource "azurerm_subnet" "db" {
  for_each             = local.db_subnets
  name                 = "snet-${local.prefix}-db-${each.key}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = each.value.vnet
  address_prefixes     = [each.value.cidr]
  delegation {
    name = "databricks"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
    }
  }
}
resource "azurerm_subnet_network_security_group_association" "db" {
  for_each                  = local.db_subnets
  subnet_id                 = azurerm_subnet.db[each.key].id
  network_security_group_id = azurerm_network_security_group.db[each.value.nsg].id
}
resource "azurerm_subnet" "data_pe" {
  name                              = "snet-${local.prefix}-data-pe"
  resource_group_name               = azurerm_resource_group.main.name
  virtual_network_name              = azurerm_virtual_network.data.name
  address_prefixes                  = ["10.41.2.0/24"]
  private_endpoint_network_policies = "Disabled"
}
resource "azurerm_public_ip" "nat" {
  for_each            = toset(["hub", "data"])
  name                = "pip-${local.prefix}-${each.key}-egress"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}
resource "azurerm_nat_gateway" "main" {
  for_each            = toset(["hub", "data"])
  name                = "nat-${local.prefix}-${each.key}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku_name            = "Standard"
  tags                = local.tags
}
resource "azurerm_nat_gateway_public_ip_association" "main" {
  for_each             = toset(["hub", "data"])
  nat_gateway_id       = azurerm_nat_gateway.main[each.key].id
  public_ip_address_id = azurerm_public_ip.nat[each.key].id
}
resource "azurerm_subnet_nat_gateway_association" "db" {
  for_each       = toset(["host", "container"])
  subnet_id      = azurerm_subnet.db[each.key].id
  nat_gateway_id = azurerm_nat_gateway.main["data"].id
}
resource "azurerm_subnet_nat_gateway_association" "runner" {
  subnet_id      = azurerm_subnet.hub["runner"].id
  nat_gateway_id = azurerm_nat_gateway.main["hub"].id
}
