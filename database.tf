resource "azurerm_postgresql_flexible_server" "openwebui" {
  name                   = "psql-${local.stack}"
  resource_group_name    = azurerm_resource_group.openwebui.name
  location               = azurerm_resource_group.openwebui.location
  version                = "16"
  administrator_login    = "openwebuiadmin"
  administrator_password = var.postgres_admin_password
  sku_name               = "B_Standard_B1ms"
  storage_mb             = 32768
  backup_retention_days  = 7

  lifecycle {
    ignore_changes = [zone]
  }

  tags = local.default_tags
}

resource "azurerm_postgresql_flexible_server_database" "openwebui" {
  name      = "openwebui"
  server_id = azurerm_postgresql_flexible_server.openwebui.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.openwebui.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
