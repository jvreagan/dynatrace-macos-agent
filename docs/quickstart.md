# Quick Start

## Prerequisites

- **macOS 14+** (Sonoma or later)
- **Dynatrace environment** with an API token
- **Xcode Command Line Tools** (if building from source)

## Option A: Install from DMG

1. Download the latest DMG from [GitHub Releases](https://github.com/jvreagan/dynatrace-macos/releases)
2. Open the DMG and drag **Dynatrace Agent** to Applications
3. Launch from Applications

## Option B: Build from Source

```bash
git clone https://github.com/jvreagan/dynatrace-macos.git
cd dynatrace-macos
bash Scripts/build-dmg.sh
open build/DynatraceAgent.dmg
```

Or run directly during development:

```bash
swift run DynatraceAgent
```

## First Launch

On first launch, the Settings window opens automatically.

### 1. Create a Dynatrace API Token

In Dynatrace → Access Tokens → Generate new token:
- **Name**: `macOS Agent`
- **Scope**: `metrics.ingest`

### 2. Configure the Agent

Fill in the Settings form:
- **Environment URL**: Your Dynatrace environment (e.g., `abc12345.live.dynatrace.com`)
- **API Token**: Paste the token from step 1

### 3. (Optional) Enable Dashboard Auto-Creation

To automatically create a metrics dashboard:
1. In Dynatrace → Account Management → OAuth Clients, create a client with scope `document:documents:write`
2. Enter the **Client ID** and **Client Secret** in Settings

### 4. Save & Start

Click **Save**. The menu bar icon turns green when metrics are flowing.

## Verify

1. **Menu bar**: Look for the chart icon — green means collecting successfully
2. **Dynatrace**: Navigate to Metrics → search for `macos.cpu.usage` — you should see data within a minute
3. **Dashboard**: If OAuth is configured, a "macOS Metrics" dashboard is created automatically

## Menu Bar

- **Settings** — Open the configuration panel
- **Live Log** — View real-time agent activity
- **Open Log File** — Reveal `~/Library/Logs/DynatraceAgent/agent.log` in Finder
- **About** — Version information
- **Quit** — Stop the agent

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Icon stays gray | Open Settings, verify environment URL and API token |
| Icon turns red | Check Live Log for error details; verify network access to Dynatrace |
| No dashboard created | Verify OAuth Client ID and Secret are configured with `document:documents:write` scope |
| Metrics missing in Dynatrace | Confirm API token has `metrics.ingest` scope |

## Next Steps

- Read [architecture.md](architecture.md) for system design details
- Read [configuration.md](configuration.md) for all settings and storage locations
