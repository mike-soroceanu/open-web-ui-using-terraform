data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "openwebui" {
  name                = "id-${local.stack}"
  location            = azurerm_resource_group.openwebui.location
  resource_group_name = azurerm_resource_group.openwebui.name

  tags = local.default_tags
}

resource "azurerm_key_vault" "openwebui" {
  name                = "kv-${local.stack}"
  location            = azurerm_resource_group.openwebui.location
  resource_group_name = azurerm_resource_group.openwebui.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enable_rbac_authorization   = true
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  tags = local.default_tags
}

# Allows the managed identity to read secrets at runtime
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.openwebui.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.openwebui.principal_id
}

# Allows Terraform (the deploying user) to create and manage secrets
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.openwebui.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "openai_api_key" {
  name         = "openai-api-key"
  value        = var.openai_api_key
  key_vault_id = azurerm_key_vault.openwebui.id

  depends_on = [azurerm_role_assignment.kv_admin]
}
