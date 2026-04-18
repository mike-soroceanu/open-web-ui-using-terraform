variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Azure infrastructure region"
  type    = string
  default = "northeurope"
}

variable "app" {
  description = "Application that we want to deploy"
  type    = string
  default = "openwebui"
}

variable "env" {
  description = "Application env"
  type    = string
  default = "dev"
}

variable "location" {
  description = "Location short name "
  type    = string
  default = "ne"
}

variable "openai_api_key" {
  description = "OpenAI API key stored in Key Vault"
  type        = string
  sensitive   = true
}

variable "postgres_admin_password" {
  description = "PostgreSQL administrator password"
  type        = string
  sensitive   = true
}