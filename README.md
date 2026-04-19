# OpenWebUI on Azure Container Apps (Terraform)

Deploys [OpenWebUI](https://github.com/open-webui/open-webui) on Azure Container Apps using Terraform.

## Architecture

- **Container App** running `ghcr.io/open-webui/open-webui:main` with 1 CPU / 2Gi memory
- **Two Azure File Shares** mounted for persistent storage:
  - `/app/chat_frontend/models` — model files
  - `/app/backend/data` — SQLite database, uploads, caches (mounted with `nobrl` to disable SMB byte-range locking, required for SQLite compatibility)
- **Key Vault** storing secrets, accessed at runtime via User-Assigned Managed Identity
- **Custom domain** (`chat.neurodribbler.com`) with Azure-managed TLS certificate
- **CPU-based autoscaling** — min 1 replica, max 10, scales at 75% CPU utilisation
- **Health probes** — startup, liveness, and readiness on `/health`

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated
- An Azure subscription
- An OpenAI API key

## Authentication

Log in to Azure before running Terraform:

```bash
az login
az account set --subscription "<your-subscription-id>"
```

## Configuration

Secrets are passed as environment variables — never stored in files on disk.

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

These variables exist only for the duration of your terminal session and are never written to disk. Terraform picks them up automatically via the `TF_VAR_*` convention.

Optional variables (defaults shown):

| Variable | Default | Description |
|---|---|---|
| `region` | `northeurope` | Azure region |
| `app` | `openwebui` | Application name used in resource naming |
| `env` | `dev` | Environment name used in resource naming |
| `location` | `ne` | Short location code used in resource naming |

## Deploy

```bash
terraform init
terraform plan
terraform apply
```

After a successful apply, outputs include:

```
container_app_url              = "https://<fqdn>.azurecontainerapps.io"
custom_domain_verification_id  = "<verification-id>"
container_app_fqdn             = "<fqdn>.azurecontainerapps.io"
key_vault_uri                  = "https://kv-openwebui-dev-ne.vault.azure.net/"
```

## Custom Domain

The deployment binds `chat.neurodribbler.com` with a managed TLS certificate. Two DNS records are required in your registrar:

| Type | Host | Value |
|---|---|---|
| TXT | `asuid.chat` | Value from `custom_domain_verification_id` output |
| CNAME | `chat` | Value from `container_app_fqdn` output |

DNS must propagate before the managed certificate can be issued. After `terraform apply`, manually bind the certificate in the Azure Portal:

> Container App → Custom domains → Add binding → select the managed certificate

## Verifying the Deployment

```bash
# Stream live logs
az containerapp logs show \
  --name ca-openwebui-dev-ne-mike \
  --resource-group rg-openwebui-dev-ne \
  --follow

# List revisions
az containerapp revision list \
  --name ca-openwebui-dev-ne-mike \
  --resource-group rg-openwebui-dev-ne \
  -o table

# Check secrets are present in Key Vault
az keyvault secret list \
  --vault-name kv-openwebui-dev-ne \
  --query "[].name" -o tsv
```

## Persistent Data

User accounts, settings, and chat history are stored in SQLite at `/app/backend/data/webui.db` on the Azure File Share. To inspect:

```bash
az storage file download \
  --account-name stopenwebuidevnemike \
  --share-name data \
  --path webui.db \
  --dest ./webui.db
```

Open with [DB Browser for SQLite](https://sqlitebrowser.org/) to inspect tables.

## Destroy

```bash
terraform destroy
```

> Key Vault has soft-delete enabled with a 7-day retention period. If you redeploy within that window, purge the deleted vault first:
> ```bash
> az keyvault purge --name kv-openwebui-dev-ne
> ```

## Resources Created

| Resource | Name | Description |
|---|---|---|
| Resource Group | `rg-openwebui-dev-ne` | Container for all resources |
| Storage Account | `stopenwebuidevnemike` | Hosts the two persistent file shares |
| File Share | `models` | Mounted at `/app/chat_frontend/models` |
| File Share | `data` | Mounted at `/app/backend/data` (with `nobrl`) |
| Container App Environment | `cae-openwebui-dev-ne-mike` | Shared environment |
| Container App | `ca-openwebui-dev-ne-mike` | Runs OpenWebUI |
| User-Assigned Identity | `id-openwebui-dev-ne` | Runtime identity for Key Vault access |
| Key Vault | `kv-openwebui-dev-ne` | Stores `openai-api-key` secret |
| Managed Certificate | `cert-openwebui-dev-ne` | TLS certificate for custom domain |
