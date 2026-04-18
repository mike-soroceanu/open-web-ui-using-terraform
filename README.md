# OpenWebUI on Azure Container Apps (Terraform)

Deploys [OpenWebUI](https://github.com/open-webui/open-webui) on Azure Container Apps using Terraform.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated
- An Azure subscription

## Authentication

Log in to Azure before running Terraform:

```bash
az login
az account set --subscription "<your-subscription-id>"
```

## Configuration

Create a `terraform.tfvars` file (never commit this file):

```hcl
subscription_id = "<your-azure-subscription-id>"
region          = "northeurope"
app             = "openwebui"
env             = "dev"
location        = "ne"
```

> `terraform.tfvars` is listed in `.gitignore` to prevent accidental credential exposure.

## Deploy

```bash
terraform init
terraform plan
terraform apply
```

After a successful apply, the OpenWebUI URL is printed as an output:

```
container_app_url = "https://<fqdn>"
```

## Destroy

```bash
terraform destroy
```

## Resources Created

| Resource | Description |
|---|---|
| Resource Group | Container for all resources |
| Container App Environment | Shared environment for container apps |
| Container App | OpenWebUI running on `ghcr.io/open-webui/open-webui:main` |
| Storage Account | Persistent storage for models and data |
| User-Assigned Managed Identity | Secure access to Key Vault secrets |
| Key Vault | Stores application secrets |

## Inputs

| Variable | Description | Default |
|---|---|---|
| `subscription_id` | Azure subscription ID | — |
| `region` | Azure region | `northeurope` |
| `app` | Application name | `openwebui` |
| `env` | Environment name | `dev` |
| `location` | Short location code for naming | `ne` |
