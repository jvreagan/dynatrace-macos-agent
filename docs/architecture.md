# Architecture

## Overview

Dynatrace macOS Agent is a menu bar application that collects system metrics from macOS and sends them to Dynatrace via the MINT ingest API. It runs as an accessory app (no dock icon) with a status bar indicator.

## Component Architecture

```
┌─────────────────────────────────────────────────────────┐
│  AppDelegate (Orchestrator)                             │
│  - Lifecycle management                                 │
│  - Timer loop (configurable interval)                   │
│  - State transitions: idle → collecting → error         │
│  - Dashboard auto-creation                              │
├─────────────────────────────────────────────────────────┤
│  MetricsCollector                                       │
│  ├── CPUMetrics        (host_processor_info)            │
│  ├── MemoryMetrics     (host_statistics64)              │
│  ├── DiskMetrics       (FileManager)                    │
│  ├── DiskIOMetrics     (Darwin syscalls)                │
│  ├── NetworkMetrics    (getifaddrs)                     │
│  ├── BatteryMetrics    (IOKit)                          │
│  ├── ThermalMetrics    (IOKit)                          │
│  ├── GPUMetrics        (Metal)                          │
│  ├── ProcessMetrics    (ProcessInfo)                    │
│  ├── SystemLoadMetrics (getloadavg)                     │
│  └── SwapMetrics       (sysctlbyname)                   │
├─────────────────────────────────────────────────────────┤
│  Services                                               │
│  ├── DynatraceAPI       → MINT ingest (/api/v2/metrics) │
│  ├── OAuthManager       → Token acquisition (SSO)       │
│  ├── DashboardService   → Auto-dashboard (Documents API)│
│  ├── ConfigurationManager → UserDefaults + @Published   │
│  ├── KeychainService    → Secure credential storage     │
│  └── LogManager         → Memory + file + os.log        │
├─────────────────────────────────────────────────────────┤
│  UI (SwiftUI + AppKit)                                  │
│  ├── MenuBarManager     → Status item, menu, icon color │
│  ├── SettingsView       → Credentials, interval, options│
│  ├── LogView            → Real-time log viewer          │
│  └── AboutView          → Version info                  │
└─────────────────────────────────────────────────────────┘
```

## Data Flow

1. **Collection**: Timer fires every N seconds → `MetricsCollector.collect()` delegates to 11 specialized collectors → returns `[MetricPoint]`

2. **Serialization**: Each `MetricPoint` serializes to Dynatrace MINT line format:
   ```
   metric.key,dim1=val1,dim2=val2 gauge,<value> <timestamp_ms>
   ```

3. **Ingestion**: `DynatraceAPI.send()` batches up to 1000 metrics per request → `POST /api/v2/metrics/ingest` with Api-Token authentication → 3 retries with exponential backoff on failure

4. **Status**: Success resets failure counter, updates menu bar to green. After 3 consecutive failures, status turns red and a macOS notification is sent.

## Metric Collection

All metrics are collected via Darwin/Mach kernel APIs — no external dependencies or shell commands:

| Category | API | Metrics |
|----------|-----|---------|
| CPU | `host_processor_info()` | usage %, user %, system %, idle % |
| Memory | `host_statistics64()` | total, used, free, active, wired, compressed, usage % |
| Disk | `FileManager` | usage % per volume |
| Disk I/O | Darwin syscalls | read/write bytes/s per device |
| Network | `getifaddrs()` | bytes in/out, errors, drops per interface |
| Battery | IOKit | level %, charging state, cycle count, time remaining |
| Thermal | IOKit | thermal state (0–3) |
| GPU | Metal | utilization %, VRAM used/free |
| Processes | ProcessInfo | count, top 5 by memory |
| Load | `getloadavg()` | 1m, 5m, 15m averages |
| Swap | `sysctlbyname()` | used, usage % |

## Dashboard Auto-Creation

On first run with OAuth credentials configured:

1. `OAuthManager` obtains access token from `https://sso.dynatrace.com/sso/oauth2/token` (client credentials flow, tokens cached with 60s expiry buffer)
2. `DashboardService` creates a 12-tile dashboard via the Dynatrace Documents API (multipart form-data)
3. Dashboard includes pre-built DQL queries for all metric categories
4. Dashboard ID stored in UserDefaults to avoid re-creation

## Security

- **API Token**: Stored in macOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **OAuth Client Secret**: Stored in macOS Keychain
- **No external dependencies**: Zero third-party packages — all functionality from Apple frameworks and standard library

## Menu Bar States

| State | Icon Color | Meaning |
|-------|-----------|---------|
| Idle | Gray | Not yet collecting |
| Collecting | Green | Active, metrics sending successfully |
| Warning | Yellow | Transient error (1–2 failures) |
| Error | Red | 3+ consecutive failures |
