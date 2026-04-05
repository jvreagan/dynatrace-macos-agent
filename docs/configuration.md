# Configuration Reference

Dynatrace macOS Agent is configured through the Settings UI (accessible from the menu bar). Settings are stored in UserDefaults with credentials secured in the macOS Keychain.

## Settings

### Dynatrace Connection

| Setting | Storage | Description |
|---------|---------|-------------|
| **Environment URL** | UserDefaults | Dynatrace environment (e.g., `abc12345.live.dynatrace.com`) |
| **API Token** | Keychain | Token with `metrics.ingest` scope |

### OAuth (Dashboard Auto-Creation)

| Setting | Storage | Description |
|---------|---------|-------------|
| **OAuth Client ID** | UserDefaults | OAuth client from Dynatrace → Account Management |
| **OAuth Client Secret** | Keychain | Client secret (scope: `document:documents:write`) |

### Dashboard

| Setting | Default | Description |
|---------|---------|-------------|
| **Dashboard Name** | `macOS Metrics` | Name for the auto-created Dynatrace dashboard |

### Collection

| Setting | Default | Description |
|---------|---------|-------------|
| **Collection Interval** | 60s | How often metrics are collected and sent (10s, 30s, 1m, 2m, 5m) |
| **Hostname Override** | *(system hostname)* | Custom hostname for metric dimensions |
| **Launch at Login** | Off | Start agent automatically on login |

## Dynatrace Token Scopes

### API Token (Required)

Create in Dynatrace → Access Tokens:
- **Scope**: `metrics.ingest` (Ingest metrics)

### OAuth Client (Optional — for dashboard creation)

Create in Dynatrace → Account Management → OAuth Clients:
- **Scope**: `document:documents:write`
- **Grant type**: Client credentials

## Storage Locations

| Data | Location |
|------|----------|
| Settings | `~/Library/Preferences/` (UserDefaults) |
| API Token | macOS Keychain (service: `com.dynatrace.macosagent`, account: `api-token`) |
| OAuth Secret | macOS Keychain (service: `com.dynatrace.macosagent`, account: `oauth-client-secret`) |
| Dashboard ID | UserDefaults (stored after creation) |
| Log File | `~/Library/Logs/DynatraceAgent/agent.log` (rotated at 5 MB) |

## API Endpoints Used

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `POST /api/v2/metrics/ingest` | Api-Token | Send metrics (MINT line protocol) |
| `POST /sso/oauth2/token` | Client credentials | Obtain OAuth access token |
| Documents API | OAuth Bearer | Create/verify dashboards |

## Network

The agent makes outbound HTTPS requests only:
- `https://<environment>.live.dynatrace.com` — metric ingest
- `https://sso.dynatrace.com` — OAuth token endpoint
- `https://<environment>.apps.dynatrace.com` — Documents API (dashboards)
