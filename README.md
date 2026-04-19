# OpenWebUI on Azure Container Apps — Terraform

Deploys [OpenWebUI](https://github.com/open-webui/open-webui) on Azure Container Apps using Terraform. Built and tested as part of a hands-on infrastructure assessment.

## Architecture

- **Container App** running `ghcr.io/open-webui/open-webui:main` with 1 CPU / 2Gi memory
- **Two Azure File Shares** for persistent storage:
  - `/app/chat_frontend/models` — model files
  - `/app/backend/data` — SQLite database, uploads, caches
- **Key Vault** storing the OpenAI API key, read at runtime via a User-Assigned Managed Identity
- **Custom domain** (`chat.neurodribbler.com`) with a managed TLS certificate
- **CPU autoscaling** — min 1 replica, max 10, threshold at 75%
- **Health probes** — startup, liveness, and readiness all on `/health`

## A Note on SQLite over Azure Files

Mounting `/app/backend/data` over Azure Files (SMB) causes SQLite to throw `database is locked` errors. SMB does not support POSIX byte-range locking, which SQLite relies on. The fix is the `nobrl` mount option on the data volume, which disables byte-range lock requests to the server. This is set in the `volume` block in `main.tf`:

```hcl
volume {
  name          = "data"
  storage_type  = "AzureFile"
  storage_name  = azurerm_container_app_environment_storage.data.name
  mount_options = "nobrl"
}
```

This was not obvious and took some digging — worth knowing if you hit this with any other SQLite-backed app on Azure Files.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated
- An Azure subscription
- An OpenAI API key

## Authentication

```bash
az login
az account set --subscription "<your-subscription-id>"
```

## Configuration

No `terraform.tfvars` file is used. Secrets are passed as shell environment variables so nothing sensitive is written to disk.

**Linux / macOS:**
```bash
export TF_VAR_subscription_id="<your-azure-subscription-id>"
export TF_VAR_openai_api_key="<your-openai-api-key>"
```

**Windows (PowerShell):**
```powershell
$env:TF_VAR_subscription_id="<your-azure-subscription-id>"
$env:TF_VAR_openai_api_key="<your-openai-api-key>"
```

Terraform picks these up automatically. They disappear when the terminal session ends.

Optional variables with defaults:

| Variable | Default | Description |
|---|---|---|
| `region` | `northeurope` | Azure region |
| `app` | `openwebui` | Application name used in resource naming |
| `env` | `dev` | Environment name |
| `location` | `ne` | Short location code for resource naming |

## First-Run Access

On a fresh deployment, OpenWebUI has no users. The first person to visit the URL is prompted to register — that account automatically becomes the admin. There is no default username or password.

If you are evaluating this deployment and need access to the live instance at `https://chat.neurodribbler.com`, contact the repository owner to have an account created in advance.

## A Note on the Custom Domain

The custom domain (`chat.neurodribbler.com`) is tied to a domain registered at a specific registrar. If you deploy this from scratch into your own Azure subscription, the custom domain step will not apply — you would use the default `*.azurecontainerapps.io` URL from the `container_app_url` output instead. Everything else deploys without modification.

## Deploy

```bash
terraform init
terraform plan
terraform apply
```

Outputs after apply:

```
container_app_url              = "https://<fqdn>.azurecontainerapps.io"
custom_domain_verification_id  = "<value>"
container_app_fqdn             = "<fqdn>.azurecontainerapps.io"
key_vault_uri                  = "https://kv-openwebui-dev-ne.vault.azure.net/"
```

## Custom Domain Setup

Two DNS records are needed at your registrar before the certificate can be issued:

| Type | Host | Value |
|---|---|---|
| TXT | `asuid.chat` | `custom_domain_verification_id` output value |
| CNAME | `chat` | `container_app_fqdn` output value |

After DNS propagates and `terraform apply` completes, the certificate will be provisioned but not yet bound. Due to a current limitation in the azurerm provider, the final binding step must be done manually:

> Azure Portal → Container App → Custom domains → click **Add binding** next to `chat.neurodribbler.com` → select the managed certificate → Save

After this, `https://chat.neurodribbler.com` will serve over HTTPS with a valid certificate.

## Verifying the Deployment

```bash
# Stream live logs
az containerapp logs show \
  --name ca-openwebui-dev-ne-mike \
  --resource-group rg-openwebui-dev-ne \
  --follow

# Check revision status
az containerapp revision list \
  --name ca-openwebui-dev-ne-mike \
  --resource-group rg-openwebui-dev-ne \
  -o table

# Confirm secrets are in Key Vault
az keyvault secret list \
  --vault-name kv-openwebui-dev-ne \
  --query "[].name" -o tsv
```

## Persistent Data

User accounts, settings, and chat history are stored in SQLite at `/app/backend/data/webui.db` on the Azure File Share. To download and inspect locally:

```bash
az storage file download \
  --account-name stopenwebuidevnemike \
  --share-name data \
  --path webui.db \
  --dest ./webui.db
```

Open with [DB Browser for SQLite](https://sqlitebrowser.org/).

## Destroy

```bash
terraform destroy
```

Key Vault has a 7-day soft-delete retention period. If you redeploy within that window:

```bash
az keyvault purge --name kv-openwebui-dev-ne
```

## Resources Created

| Resource | Name | Description |
|---|---|---|
| Resource Group | `rg-openwebui-dev-ne` | Container for all resources |
| Storage Account | `stopenwebuidevnemike` | Hosts the two persistent file shares |
| File Share | `models` | Mounted at `/app/chat_frontend/models` |
| File Share | `data` | Mounted at `/app/backend/data` (with `nobrl`) |
| Container App Environment | `cae-openwebui-dev-ne-mike` | Shared hosting environment |
| Container App | `ca-openwebui-dev-ne-mike` | Runs OpenWebUI |
| User-Assigned Identity | `id-openwebui-dev-ne` | Runtime identity for Key Vault access |
| Key Vault | `kv-openwebui-dev-ne` | Stores the `openai-api-key` secret |
| Managed Certificate | `cert-openwebui-dev-ne` | TLS certificate for custom domain |

## Useful Links

- [OpenWebUI GitHub](https://github.com/open-webui/open-webui) — source and image for the deployed app
- [azurerm Container App — Terraform Registry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app) — provider docs, including the `volume` block and `mount_options`
- [Azure Container Apps overview](https://learn.microsoft.com/en-us/azure/container-apps/overview) — concepts around revisions, scaling, and ingress
- [Azure Files mount options (SMB)](https://learn.microsoft.com/en-us/azure/aks/azure-files-volume) — where `nobrl` and other SMB mount options are documented
- [Managed certificates in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates) — custom domain and certificate binding walkthrough
- [Key Vault RBAC guide](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide) — how RBAC roles work with Key Vault vs access policies
- [DB Browser for SQLite](https://sqlitebrowser.org/) — useful for inspecting the `webui.db` file from the data share
- [Manual Deployment of OpenWebUI via the Azure Portal](https://blakedrumm.com/blog/azure-container-apps-openweb-ui/) - how the deployment would work manually via the Azure Portal, which enabled me to find the nobrl mount option
- [Mount Options for Azure File Shares based on type](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/storage/mountoptions-settings-azure-files#other-useful-settings) - the nobrl mount option find
