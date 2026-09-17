resource "azurerm_databricks_workspace" "main" {
  name                                  = "dbw-${local.prefix}-de"
  resource_group_name                   = azurerm_resource_group.main.name
  location                              = var.location
  sku                                   = "premium"
  managed_resource_group_name           = "managed-rg-${local.prefix}-de"
  public_network_access_enabled         = false
  network_security_group_rules_required = "NoAzureDatabricksRules"
  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = azurerm_virtual_network.data.id
    public_subnet_name                                   = azurerm_subnet.db["host"].name
    private_subnet_name                                  = azurerm_subnet.db["container"].name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.db["host"].id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.db["container"].id
  }
  tags       = local.tags
  depends_on = [azurerm_subnet_nat_gateway_association.db]
}
resource "azurerm_databricks_workspace" "auth" {
  depends_on = [
    azurerm_databricks_workspace.main
  ]
  name                                  = "dbw-${local.prefix}-web-auth"
  resource_group_name                   = azurerm_resource_group.main.name
  location                              = var.location
  sku                                   = "premium"
  managed_resource_group_name           = "managed-rg-${local.prefix}-web-auth"
  public_network_access_enabled         = false
  network_security_group_rules_required = "NoAzureDatabricksRules"
  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = azurerm_virtual_network.hub.id
    public_subnet_name                                   = azurerm_subnet.db["authhost"].name
    private_subnet_name                                  = azurerm_subnet.db["authcontainer"].name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.db["authhost"].id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.db["authcontainer"].id
  }
  tags = local.tags
  lifecycle { prevent_destroy = true }
}
resource "azurerm_storage_account" "lake" {
  name                            = "st${module.naming.compact}dl"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  tags                            = local.tags
  lifecycle { prevent_destroy = true }
}
resource "azurerm_storage_container" "lake" {
  for_each              = toset(["landing", "unity"])
  name                  = each.key
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}
resource "azurerm_databricks_access_connector" "uc" {
  name                = "ac-${local.prefix}-uc"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  identity { type = "SystemAssigned" }
  tags = local.tags
}
resource "azurerm_role_assignment" "uc_storage" {
  for_each             = azurerm_storage_container.lake
  scope                = "${azurerm_storage_account.lake.id}/blobServices/default/containers/${each.key}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.uc.identity[0].principal_id
}
resource "azurerm_key_vault" "apps" {
  name                          = "kv-${module.naming.compact}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  tags                          = local.tags
  lifecycle { prevent_destroy = true }
}
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}
locals {
  endpoints = {
    blob      = { id = azurerm_storage_account.lake.id, group = "blob", zone = "privatelink.blob.core.windows.net", subnet = azurerm_subnet.data_pe.id }
    dfs       = { id = azurerm_storage_account.lake.id, group = "dfs", zone = "privatelink.dfs.core.windows.net", subnet = azurerm_subnet.data_pe.id }
    vault     = { id = azurerm_key_vault.apps.id, group = "vault", zone = "privatelink.vaultcore.azure.net", subnet = azurerm_subnet.data_pe.id }
    workspace = { id = azurerm_databricks_workspace.main.id, group = "databricks_ui_api", zone = "privatelink.azuredatabricks.net", subnet = azurerm_subnet.data_pe.id }
    auth      = { id = azurerm_databricks_workspace.auth.id, group = "browser_authentication", zone = "privatelink.azuredatabricks.net", subnet = azurerm_subnet.hub["endpoints"].id }
    state     = { id = var.state_account_id, group = "blob", zone = "privatelink.blob.core.windows.net", subnet = azurerm_subnet.hub["endpoints"].id }
  }
  dns_zones = toset([for e in local.endpoints : e.zone])
  dns_links = { for p in setproduct(local.dns_zones, ["hub", "data"]) : "${p[0]}-${p[1]}" => { zone = p[0], vnet = p[1] } }
}
resource "azurerm_private_dns_zone" "main" {
  for_each            = local.dns_zones
  name                = each.key
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  for_each              = local.dns_links
  name                  = "link-${each.value.vnet}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.main[each.value.zone].name
  virtual_network_id    = each.value.vnet == "hub" ? azurerm_virtual_network.hub.id : azurerm_virtual_network.data.id
  registration_enabled  = false
  tags                  = local.tags
}
resource "azurerm_private_endpoint" "main" {
  for_each            = local.endpoints
  name                = "pe-${local.prefix}-${each.key}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  subnet_id           = each.value.subnet
  private_service_connection {
    name                           = "psc-${each.key}"
    private_connection_resource_id = each.value.id
    subresource_names              = [each.value.group]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.main[each.value.zone].id]
  }
  tags = local.tags
}
resource "azurerm_monitor_diagnostic_setting" "kv" {
  name                       = "diag-${local.prefix}-kv"
  target_resource_id         = azurerm_key_vault.apps.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  enabled_log { category_group = "allLogs" }
}
resource "azurerm_monitor_diagnostic_setting" "db" {
  name                       = "diag-${local.prefix}-db"
  target_resource_id         = azurerm_databricks_workspace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  enabled_log { category_group = "allLogs" }
}
resource "azurerm_monitor_diagnostic_setting" "blob" {
  name                       = "diag-${local.prefix}-blob"
  target_resource_id         = "${azurerm_storage_account.lake.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  enabled_log { category_group = "allLogs" }
}
