# Dynatrace macOS Agent

A lightweight macOS menu bar app that collects system metrics and sends them to your Dynatrace environment. Automatically creates a dashboard so you can start observing your Mac in minutes.

## What it monitors

| Metric | Description |
|--------|-------------|
| CPU usage | Total, user, system, idle |
| Memory | Used, free, active, wired, compressed |
| Disk | Usage % per device |
| Network | Bytes in/out per interface |
| Load average | 1m, 5m, 15m |
| Swap | Used and usage % |

All metrics are tagged with `host.name` so you can monitor multiple Macs from one environment.

## Requirements

- macOS 14 (Sonoma) or later
- A Dynatrace environment (SaaS)
- Two Dynatrace credentials (setup instructions below)

## Installation

1. Download `DynatraceAgent.dmg` from the [latest release](../../releases/latest)
2. Open the DMG and drag **Dynatrace Agent** to your **Applications** folder
3. Launch **Dynatrace Agent** from Applications
4. A setup screen will appear — follow the steps below

> **Note:** On first launch macOS may warn the app is from an unidentified developer. Right-click the app in Finder and choose **Open** to bypass this.

## Setup

You need two things from your Dynatrace environment:

### 1. API Token (for sending metrics)

1. In Dynatrace, use the search bar and search for **Access Tokens**, then click **Generate new token**
2. Give it a name (e.g. `macos-agent`)
3. Add the scope: **`metrics.ingest`**
4. Copy the token

### 2. OAuth Client (for the dashboard)

1. In Dynatrace, go to **Account Management → Identity & Access Management → OAuth Clients → Create client**
2. Give it a name (e.g. `macos-agent-dashboard`)
3. Add the scope: **`document:documents:write`**
4. Copy the **Client ID** and **Client Secret**

### In the app

Fill in the setup screen:

- **Environment URL** — your Dynatrace hostname, e.g. `abc12345.live.dynatrace.com`
- **API Token** — the token from step 1
- **Dashboard Name** — whatever you want to call it (default: `macOS Metrics`)
- **OAuth Client ID** — from step 2
- **OAuth Client Secret** — from step 2

Click **Save & Start Running**. The app will connect, create your dashboard, and start sending metrics immediately.

## Usage

The app runs in your menu bar.

| Icon | Meaning |
|------|---------|
| Green bars | Running — metrics are being sent |
| Gray bars | Idle |
| Red bars | Error — check Settings |

**Menu options:**
- **Settings...** — update credentials or configuration
- **View Logs...** — see what the agent is doing
- **Quit** — stop the agent

The agent starts automatically when you launch it. Quit the app to stop it.

## Building from source

Requires Xcode command line tools and Swift 5.9+.

```bash
git clone https://github.com/your-username/dynatrace-macos-agent
cd dynatrace-macos-agent
Scripts/build-dmg.sh
```

Then open `build/DynatraceAgent.dmg` and drag the app to Applications.

## License

MIT
