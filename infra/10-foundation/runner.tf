variable "enable_runner_vm" { default = false }
variable "runner_ssh_public_key" { default = "" }
resource "azurerm_network_security_group" "runner" {
  name                = "nsg-${local.prefix}-runner"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  security_rule {
    name                       = "SSHFromVPN"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "172.30.240.0/24"
    destination_address_prefix = "10.40.2.0/24"
  }
  security_rule {
    name                       = "DenyOtherInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = local.tags
}
resource "azurerm_subnet_network_security_group_association" "runner" {
  subnet_id                 = azurerm_subnet.hub["runner"].id
  network_security_group_id = azurerm_network_security_group.runner.id
}
resource "azurerm_network_interface" "runner" {
  count               = var.enable_runner_vm ? 1 : 0
  name                = "nic-${local.prefix}-runner"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.hub["runner"].id
    private_ip_address_allocation = "Dynamic"
  }
  tags = local.tags
}
resource "azurerm_linux_virtual_machine" "runner" {
  count                           = var.enable_runner_vm ? 1 : 0
  name                            = "vm-${local.prefix}-runner"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = var.location
  size                            = "Standard_D2s_v5"
  admin_username                  = "mqgenadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.runner[0].id]
  admin_ssh_key {
    username   = "mqgenadmin"
    public_key = var.runner_ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  tags = local.tags
  lifecycle {
    precondition {
      condition     = length(var.runner_ssh_public_key) > 30
      error_message = "Supply the public SSH key before enabling the runner VM."
    }
  }
}
output "runner_private_ip" { value = try(azurerm_network_interface.runner[0].private_ip_address, null) }
