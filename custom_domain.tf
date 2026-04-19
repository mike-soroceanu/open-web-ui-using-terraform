resource "azurerm_container_app_environment_managed_certificate" "openwebui" {
  name                         = "cert-${local.stack}"
  container_app_environment_id = azurerm_container_app_environment.openwebui.id
  subject_name                 = "chat.neurodribbler.com"
}

resource "azurerm_container_app_custom_domain" "openwebui" {
  name                     = "chat.neurodribbler.com"
  container_app_id         = azurerm_container_app.openwebui.id
  certificate_binding_type = "SniEnabled"

  depends_on = [azurerm_container_app_environment_managed_certificate.openwebui]
}
