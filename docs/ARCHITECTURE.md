# Architecture — testapp-node

> **Owner:** Alban Fetahi (`afetahi`) · **Purpose:** demo workload for Azure SRE Agent labs
> **Source:** this repository · **Infrastructure as code:** [`infra/main.bicep`](../infra/main.bicep)

## Overview

`testapp-node` is a small Node.js (Express) web app on Azure App Service (Linux). It serves a landing
page and two JSON APIs. It also has opt-in fault-injection endpoints, so incidents can be simulated
on purpose. It has **no database, cache, queue or other downstream dependency**.

## Azure resources

All resources are in subscription `ME-MngEnvMCAP142510-albanfetahi-3`, resource group
`rg-testapp-node`, region **Sweden Central**.

| Resource | Name | Purpose |
|---|---|---|
| App Service plan | `testapp-node-plan` | Linux, **Basic B1** (1 core, 1.75 GB), **one instance**, no autoscale |
| Web app | `testapp-node-2rqjmu` | Runtime `NODE\|24-lts`, Always On, HTTPS only, health check `/api/health` |
| Application Insights | `testapp-node-ai` | Request, dependency and exception telemetry (workspace-based) |
| Log Analytics workspace | `testapp-node-law` | Stores App Insights data and App Service logs, 30-day retention |
| Managed identity | `id-github-testapp-node` | Used **only** by GitHub Actions to deploy (Website Contributor on the web app) |

Public URL: `https://testapp-node-2rqjmu.azurewebsites.net`

There are **no deployment slots**: every deployment goes straight to production.

## Endpoints

| Route | Purpose |
|---|---|
| `GET /` | Landing page. It polls `/api/info` every 2 s while open. |
| `GET /api/health` | Liveness check, also used by the App Service health check |
| `GET /api/info` | Instance details: site name, region, Node version, uptime, visits |
| `GET /api/chaos` | Shows whether fault injection is enabled, plus current CPU and memory fault load |
| `/api/slow`, `/api/error`, `/api/cpu`, `/api/memory`, `/api/memory/release` | Fault injection. Returns `404` unless `CHAOS_ENABLED=true`. See the [README](../README.md). |

## Configuration (app settings)

| Setting | Value | Effect |
|---|---|---|
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | set by Bicep | Turns on Azure Monitor OpenTelemetry in `app.js` |
| `CHAOS_ENABLED` | `false` by default | `true` turns on the fault-injection endpoints |
| `GREETING_NAME` | not set (defaults to `Alban`) | Name shown on the landing page |

Changing any app setting **restarts the app**.

## Deployment

1. A push to `master` (or a manual run) starts [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml).
2. **Build job:** Node 24, `npm ci`, upload the artifact.
3. **Deploy job:** signs in to Azure with **OpenID Connect**: GitHub issues a short-lived token, and
   the federated credential on `id-github-testapp-node` trusts it for this repo's `master` branch
   only. The job then deploys the artifact to the web app with `azure/webapps-deploy`.
4. Basic-auth publishing (FTP/SCM) is **disabled**, so this is the only way to deploy.

Every deployment is therefore a GitHub Actions run linked to a commit on `master`. To find out what
changed before an incident, compare the incident start time with the latest workflow runs and commits.

## Telemetry: where to look

| Data | Table (in `testapp-node-law`) | Notes |
|---|---|---|
| Incoming requests (route, status, duration) | `AppRequests` | From OpenTelemetry; `Success == false` marks failures |
| Exceptions | `AppExceptions` | May be sparse, because handled errors are logged rather than thrown to the SDK |
| App console output | `AppServiceConsoleLogs` | One JSON line per request (`"msg":"request"`), plus JSON error lines with `stack` |
| HTTP access logs | `AppServiceHTTPLogs` | Front-end view: `CsUriStem`, `ScStatus`, `TimeTaken` |
| Platform events | `AppServicePlatformLogs` | Container starts and stops, restarts, health-check actions |
| Metrics | Azure Monitor metrics on the web app | CPU, memory, HTTP 5xx, response time, health-check status |

Request logs and error logs share a `requestId`, which is also returned in the `x-request-id`
response header.

## Known limitations

- A **single B1 instance**, so any restart or crash briefly takes the app offline.
- No staging slot, so a bad deployment reaches users immediately. Roll back by reverting the commit.
- Region quota: this subscription has **no App Service quota in North Europe or UK South**, so use
  Sweden Central or West Europe.
