# Dynatrace macOS Agent

A lightweight macOS menu bar app that collects system metrics and sends them to your Dynatrace environment. Automatically creates a dashboard so you can start observing your Mac in minutes.

## What it monitors

| Metric | Description |
|--------|-------------|
| CPU | Usage %, user, system, idle |
| Memory | Used, free, active, wired, compressed |
| Disk | Usage % and I/O bytes/s per device |
| Network | Bytes in/out and errors/drops per interface |
| Load average | 1m, 5m, 15m |
| Swap | Used and usage % |
| GPU | Usage % and VRAM used/free |
| Thermal | State (0=nominal → 3=critical) |
| Battery | Level %, charging state, cycle count, time remaining |
| Processes | Total count and top 5 by memory |

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
| Yellow bars | Warning — dashboard creation failed, check OAuth credentials |
| Red bars | Error — metrics failing to send, check Settings |
| Gray bars | Idle |

**Menu options:**
- **Settings...** — update credentials or collection interval
- **Live Log...** — real-time view of what the agent is doing
- **Open Log File** — reveal the persistent log in Finder (`~/Library/Logs/DynatraceAgent/agent.log`)
- **About Dynatrace Agent** — version info and links
- **Quit** — stop the agent

The agent starts automatically when you launch it. Quit the app to stop it. You can also enable **Launch at login** in Settings → Advanced.

## Notifications

The agent sends macOS notifications when:
- Metrics fail to send 3 times in a row — prompting you to check Settings
- Metrics recover after a failure — so you know it's healthy again without opening the app

## Building from source

Requires Xcode command line tools.

```bash
git clone https://github.com/your-username/dynatrace-macos-agent
cd dynatrace-macos-agent
bash Scripts/build-dmg.sh
```

Then open `build/DynatraceAgent.dmg` and drag the app to Applications.

## Releasing a new version

Tag the commit and push — CI builds the DMG and publishes the release automatically:

```bash
git tag v1.1.0
git push origin v1.1.0
```

## License

MIT
