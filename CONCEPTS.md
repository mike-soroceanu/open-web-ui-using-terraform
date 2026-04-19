# Technical Concepts — OpenWebUI on Azure Container Apps

A reference document covering all key concepts encountered during this deployment.

---

## 1. Azure Container Apps Revisions

Every time you deploy a change to a Container App, Azure creates a new **revision** — an immutable snapshot of the app configuration at that point in time.

- **Single revision mode**: Only one revision is active at a time. Traffic automatically switches to the new revision. If the new revision fails, traffic stays on the old one.
- **Multiple revision mode**: Multiple revisions can be active simultaneously, useful for A/B testing or canary deployments.

Revisions are named automatically (e.g., `ca-openwebui-dev-ne-mike--0000003`). You cannot rename them. Old failed revisions appear under "Inactive revisions" in the portal.

---

## 2. Azure Resource Providers

Azure organizes its services into **resource providers** — feature sets that must be explicitly enabled on a subscription before they can be used.

| Provider | What it covers |
|---|---|
| `Microsoft.App` | Azure Container Apps, Container App Environments |
| `Microsoft.Storage` | Storage Accounts, File Shares, Blob Storage |
| `Microsoft.DBforPostgreSQL` | PostgreSQL Flexible Server |

Some providers auto-register when you first use them via the Portal. Others require explicit registration:

```bash
az provider register -n Microsoft.App --wait
az provider register -n Microsoft.Storage --wait
```

---

## 3. Persistent Storage in Containers

Containers are **ephemeral** by nature — any data written inside a container is lost when it restarts, crashes, or scales.

### Azure Files + Container Apps
Azure Container Apps supports mounting Azure File Shares (SMB protocol) as persistent volumes. This requires four Terraform resources:

| Resource | Purpose |
|---|---|
| `azurerm_storage_account` | The Azure resource that owns and hosts file shares |
| `azurerm_storage_share` | The actual file share inside the storage account |
| `azurerm_container_app_environment_storage` | Registers the share with the CAE so it knows how to access it |
| `volume` + `volume_mounts` blocks | Maps the share into a specific path inside the container |

### Why SQLite Fails Over Azure Files (SMB)
SQLite requires **POSIX file locking** to safely read and write its database. The SMB protocol used by Azure Files does **not support POSIX file locking**. This causes `database is locked` errors regardless of how many times you restart or redeploy.

**The fix**: use a proper client-server database like **PostgreSQL**, which handles concurrent access correctly and doesn't rely on filesystem locking.

---

## 4. System-Assigned vs User-Assigned Managed Identity

Managed Identities allow Azure resources to authenticate to other Azure services (like Key Vault) without storing credentials anywhere.

| | System-Assigned | User-Assigned |
|---|---|---|
| Created | Automatically with the resource | As a standalone Azure resource |
| Lifecycle | Dies when the resource is deleted | Independent — survives resource deletion |
| Sharing | One per resource, cannot be shared | Can be shared across multiple resources |
| Terraform | `type = "SystemAssigned"` only | Requires `azurerm_user_assigned_identity` resource |

**Why User-Assigned is better for Container Apps**: If Terraform destroys and recreates the Container App (common during development), a System-Assigned identity would be destroyed too, breaking Key Vault role assignments. User-Assigned identities and their RBAC assignments survive independently.

---

## 5. Azure Key Vault and RBAC

Key Vault stores secrets, certificates, and keys securely. With **RBAC authorization** enabled (`enable_rbac_authorization = true`), access is controlled via Azure role assignments rather than access policies.

### Key Roles

| Role | Who Gets It | Purpose |
|---|---|---|
| `Key Vault Administrator` | The Terraform deploying user | Create, update, and delete secrets during deployment |
| `Key Vault Secrets User` | The Managed Identity | Read secrets at runtime inside the container |

### How Secrets Flow into the Container App

```
Key Vault Secret
      ↓ (referenced by URI + managed identity)
Container App `secret` block
      ↓ (referenced by name)
Container `env` block
      ↓
Environment variable inside the running container
```

No secret values are ever stored in Terraform state or code.

### Soft Delete
Key Vault has soft delete enabled by default. After `terraform destroy`, the vault name is reserved for the retention period (we set 7 days). If you redeploy within that window, you may need to purge the soft-deleted vault first:

```bash
az keyvault purge --name kv-openwebui-dev-ne
```

---

## 6. Health Probes in Azure Container Apps

Azure Container Apps supports three types of probes that run inside the container:

| Probe | Purpose | When it runs |
|---|---|---|
| `startup_probe` | Gives the container time to initialize before ACA starts health checking | Once, at container start |
| `liveness_probe` | Detects if the container has entered a broken state and needs a restart | Continuously while running |
| `readiness_probe` | Detects if the container is ready to receive traffic | Continuously while running |

### Key Configuration Attributes (azurerm provider)

```hcl
startup_probe {
  transport               = "HTTP"   # HTTP, HTTPS, or TCP
  path                    = "/health"
  port                    = 8080
  initial_delay           = 60       # seconds before first check
  interval_seconds        = 15       # seconds between checks
  failure_count_threshold = 10       # failures before giving up
  timeout                 = 5        # seconds to wait for response
}
```

**Why startup probes matter**: Heavy applications like OpenWebUI take 2-3 minutes to initialize (running database migrations, loading ML libraries). Without a generous startup probe, ACA will kill the container before it finishes starting.

---

## 7. KEDA — Kubernetes Event-Driven Autoscaling

Azure Container Apps uses **KEDA** under the hood to handle autoscaling. When you see `KEDAScaleTargetDeactivated` in system logs, it means KEDA scaled a revision down to 0 replicas — either because there was no traffic or because the container kept failing.

Autoscaling is configured in the `template` block:

```hcl
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
}
```

---

## 8. PostgreSQL Flexible Server

A fully managed PostgreSQL service on Azure. Key considerations:

- **Availability Zone**: Azure assigns a zone automatically on creation. Use `lifecycle { ignore_changes = [zone] }` in Terraform to prevent it from trying to change the zone on subsequent applies.
- **Firewall**: By default, no connections are allowed. Setting `start_ip_address = "0.0.0.0"` and `end_ip_address = "0.0.0.0"` in the firewall rule allows all Azure-internal services to connect.
- **SKU naming**: `B_Standard_B1ms` = Burstable tier, Standard_B1ms compute size. The burstable tier is cheapest but not for production workloads.

---

## 9. Terraform Key Concepts

### `sensitive = true`
Marks a variable or output as sensitive. Terraform will redact its value from CLI output and plan files. It does **not** prevent the value from being stored in state — state encryption is a separate concern.

### `depends_on`
Forces an explicit dependency between resources when Terraform can't infer it automatically. Example: Key Vault secrets must wait for the role assignment that gives Terraform permission to create them.

```hcl
depends_on = [azurerm_role_assignment.kv_admin]
```

### `lifecycle { ignore_changes = [...] }`
Tells Terraform to ignore drift on specific attributes after initial creation. Used for attributes that Azure manages internally (like availability zones).

### ForceNew attributes
Some resource attributes are marked **ForceNew** in the provider — changing them destroys and recreates the resource. Example: `log_analytics_workspace_id` on a Container App Environment. Always check `terraform plan` for `-/+` (destroy/create) entries before applying.

### `versionless_id` vs `id` on Key Vault Secrets
- `id` — points to a specific version of the secret
- `versionless_id` — always resolves to the latest version

Use `versionless_id` in Container App secret references so the app automatically picks up rotated secrets.

---

## 10. Debugging Azure Container Apps

### Log types

| Command flag | What it shows |
|---|---|
| `--type system` | Infrastructure events: image pulls, probe failures, KEDA scaling |
| `--type console` (default) | Stdout/stderr from the container process |

### Useful CLI commands

```bash
# Stream logs in real time
az containerapp logs show --name <app> --resource-group <rg> --follow

# List revisions and their status
az containerapp revision list --name <app> --resource-group <rg> -o table

# Show full revision details
az containerapp revision show --name <app> --resource-group <rg> --revision <name>

# List CAE storage registrations
az containerapp env storage list --name <env> --resource-group <rg> -o table

# Check Key Vault secrets
az keyvault secret list --vault-name <kv> --query "[].name" -o tsv
```

### Common failure patterns

| Symptom | Likely Cause |
|---|---|
| Activation failed, 0 replicas, no logs | Volume mount failure or secret fetch failure before container starts |
| Exit code 1, logs stop mid-initialization | OOM kill or unhandled exception in a background thread |
| `startup probe failed: connection refused` | App not yet listening on the target port — may just need more time |
| `database is locked` | SQLite over Azure Files (SMB) — switch to PostgreSQL |
| `KEDAScaleTargetDeactivated` | Container kept crashing; KEDA gave up and scaled to 0 |

---

## 11. Custom Domains and DNS Records

To bind a custom domain like `chat.neurodribbler.com` to a Container App, two DNS records are required.

### TXT Record — Domain Ownership Verification

Before Azure issues a TLS certificate, it must verify you control the domain. This is done via a TXT record:

| Field | Value |
|---|---|
| Type | TXT |
| Prefix | `asuid.<subdomain>` (e.g. `asuid.chat`) |
| Value | The `custom_domain_verification_id` from the Container App Environment |

Only the domain owner can add DNS records, so this proves to Azure that you authorised the binding. The verification ID is unique per CAE and is exposed as a Terraform output or attribute.

### CNAME Record — Traffic Routing

A CNAME (Canonical Name) maps one hostname to another hostname:

| Field | Value |
|---|---|
| Type | CNAME |
| Prefix | `chat` |
| Value | The Container App's default FQDN (e.g. `ca-openwebui-dev-ne-mike.xxx.northeurope.azurecontainerapps.io`) |

When a browser resolves `chat.neurodribbler.com`, DNS follows the CNAME chain to the Azure FQDN, and Azure routes the request to the correct Container App.

### Why Not an A Record?

An A record maps a hostname to a static IP address. Azure Container Apps does not provide a dedicated static IP — the app sits behind shared Azure infrastructure and the IP can change. A CNAME follows the chain dynamically, always resolving correctly regardless of Azure's underlying IP changes.

**The one exception**: CNAME records are forbidden on apex/root domains (`neurodribbler.com` without a subdomain) by the DNS spec. For apex domains you need either an A record with a static IP or an Azure DNS alias record. Using a subdomain (`chat.`) avoids this restriction entirely.

### Terraform Resources

```hcl
resource "azurerm_container_app_environment_managed_certificate" "openwebui" {
  name                           = "cert-${local.stack}"
  container_app_environment_id   = azurerm_container_app_environment.openwebui.id
  domain_name                    = "chat.neurodribbler.com"
  domain_control_validation_type = "CNAME"
}

resource "azurerm_container_app_custom_domain" "openwebui" {
  name                                             = "chat.neurodribbler.com"
  container_app_id                                 = azurerm_container_app.openwebui.id
  container_app_environment_managed_certificate_id = azurerm_container_app_environment_managed_certificate.openwebui.id
  certificate_binding_type                         = "SniEnabled"
}
```

Azure provisions the managed TLS certificate automatically once DNS validation passes. No certificate files or renewal management needed.
