locals {
  stack = "${var.app}-${var.env}-${var.location}"

  default_tags = {
    environment = var.env
    owner       = "M.Sor"
    app         = var.app
  }

}

resource "azurerm_resource_group" "openwebui" {
  name     = "rg-${local.stack}"
  location = var.region

  tags = local.default_tags
}

resource "azurerm_storage_account" "openwebui" {
  name                     = "st${replace(local.stack, "-", "")}mike"
  resource_group_name      = azurerm_resource_group.openwebui.name
  location                 = azurerm_resource_group.openwebui.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.default_tags
}

resource "azurerm_storage_share" "models" {
  name               = "models"
  storage_account_id = azurerm_storage_account.openwebui.id
  quota              = 50
}

resource "azurerm_storage_share" "data" {
  name               = "data"
  storage_account_id = azurerm_storage_account.openwebui.id
  quota              = 50
}

resource "azurerm_container_app_environment" "openwebui" {
  name                      = "cae-${local.stack}-mike"
  location                   = azurerm_resource_group.openwebui.location
  resource_group_name        = azurerm_resource_group.openwebui.name

  tags = local.default_tags
}

resource "azurerm_container_app_environment_storage" "models" {
  name                         = "models"
  container_app_environment_id = azurerm_container_app_environment.openwebui.id
  account_name                 = azurerm_storage_account.openwebui.name
  share_name                   = azurerm_storage_share.models.name
  access_key                   = azurerm_storage_account.openwebui.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "data" {
  name                         = "data"
  container_app_environment_id = azurerm_container_app_environment.openwebui.id
  account_name                 = azurerm_storage_account.openwebui.name
  share_name                   = azurerm_storage_share.data.name
  access_key                   = azurerm_storage_account.openwebui.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app" "openwebui" {
  name                         = "ca-${local.stack}-mike"

  container_app_environment_id = azurerm_container_app_environment.openwebui.id
  resource_group_name          = azurerm_resource_group.openwebui.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.openwebui.id]
  }

  secret {
    name                = "openai-api-key"
    key_vault_secret_id = azurerm_key_vault_secret.openai_api_key.versionless_id
    identity            = azurerm_user_assigned_identity.openwebui.id
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 8080
    traffic_weight {
      percentage = 100
      latest_revision = true
    }

  }

  template {
    min_replicas = 1
    max_replicas = 10

    custom_scale_rule {
      name             = "cpu-scaling"
      custom_rule_type = "cpu"
      metadata = {
        type  = "Utilization"
        value = "75"
      }
    }

    container {
      name   = "ca-${local.stack}"
      image  = "ghcr.io/open-webui/open-webui:main"
      cpu    = 1
      memory = "2Gi"

      env {
        name        = "OPENAI_API_KEY"
        secret_name = "openai-api-key"
      }

      startup_probe {
        transport               = "HTTP"
        path                    = "/health"
        port                    = 8080
        initial_delay           = 60
        interval_seconds        = 15
        failure_count_threshold = 30
        timeout                 = 5
      }

      volume_mounts {
        name = "models"
        path = "/app/chat_frontend/models"
      }

      volume_mounts {
        name = "data"
        path = "/app/backend/data"
      }
    }

    volume {
      name         = "models"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.models.name
    }

    volume {
      name          = "data"
      storage_type  = "AzureFile"
      storage_name  = azurerm_container_app_environment_storage.data.name
      mount_options = "nobrl"
    }
  }

  tags = local.default_tags

}