output "container_app_url" {
  description = "Stable FQDN for the Container App (use this for DNS/custom domain)"
  value       = "https://${azurerm_container_app.openwebui.ingress[0].fqdn}"
}

output "container_app_latest_revision_url" {
  description = "URL of the latest active revision"
  value       = "https://${azurerm_container_app.openwebui.latest_revision_fqdn}"
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.openwebui.name
}

output "container_app_environment_id" {
  description = "ID of the Container App Environment"
  value       = azurerm_container_app_environment.openwebui.id
}

output "storage_account_name" {
  description = "Name of the storage account holding persistent file shares"
  value       = azurerm_storage_account.openwebui.name
}

output "managed_identity_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.openwebui.client_id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.openwebui.vault_uri
}

output "custom_domain_verification_id" {
  description = "TXT record value for custom domain ownership verification"
  value       = azurerm_container_app_environment.openwebui.custom_domain_verification_id
}

output "container_app_fqdn" {
  description = "Default FQDN to use as CNAME target"
  value       = azurerm_container_app.openwebui.ingress[0].fqdn
}
