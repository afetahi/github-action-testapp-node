# Runbook — testapp-node

> **Service:** `testapp-node-2rqjmu` (App Service, `rg-testapp-node`, Sweden Central)
> **Owner:** Alban Fetahi (`afetahi`) · **Architecture:** [ARCHITECTURE.md](ARCHITECTURE.md)

Use this runbook when the app is unavailable, returns errors, or is slow.

## 1. Confirm the symptom

```bash
curl -s -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" https://testapp-node-2rqjmu.azurewebsites.net/api/health
curl -s https://testapp-node-2rqjmu.azurewebsites.net/api/chaos
```

- `/api/health` should return `200` in under 1 s.
- If `/api/chaos` shows `"enabled": true`, fault injection is on, and the symptoms may be a planned
  lab scenario. Check with the owner before treating it as an incident.

## 2. Check what changed

1. **Recent deployments:** check the latest GitHub Actions runs of *Build and deploy Node.js app to
   Azure Web App* and the commits on `master`. A deployment just before the symptoms started is the
   most likely cause.
2. **Configuration changes:** check the Activity Log of `testapp-node-2rqjmu`. An app-setting change
   (for example `CHAOS_ENABLED`) restarts the app.

## 3. Diagnose with logs (Log Analytics workspace `testapp-node-law`)

Failed requests by route in the last hour:

```kusto
AppRequests
| where TimeGenerated > ago(1h)
| summarize Total = count(), Failed = countif(Success == false), P95ms = percentile(DurationMs, 95) by Name
| order by Failed desc
```

Error lines and stack traces from the app's console output:

```kusto
AppServiceConsoleLogs
| where TimeGenerated > ago(1h)
| where ResultDescription has '"level":"error"'
| project TimeGenerated, ResultDescription
| order by TimeGenerated desc
```

Slow requests (over 2 s) at the front end:

```kusto
AppServiceHTTPLogs
| where TimeGenerated > ago(1h) and TimeTaken > 2000
| summarize Count = count(), P95ms = percentile(TimeTaken, 95) by CsUriStem
| order by Count desc
```

Restarts and platform events:

```kusto
AppServicePlatformLogs
| where TimeGenerated > ago(6h)
| project TimeGenerated, Level, OperationName, Message
| order by TimeGenerated desc
```

Also check the web app's metrics for CPU, memory working set, HTTP 5xx and response time.

## 4. Common causes and safe actions

| Symptom | Likely cause | Action |
|---|---|---|
| 500s on one route, stack traces in console logs | Bug in recent code, or `/api/error` fault | Find the commit; revert it on `master` to redeploy the last good version |
| High latency on one route | `/api/slow` fault, or slow code path | Check `/api/chaos`; compare with the latest deployment |
| High CPU, slow responses everywhere | `/api/cpu` fault or a hot loop | CPU faults stop by themselves within 30 s; otherwise restart |
| Memory growing, possible restarts | `/api/memory` fault or a leak | Call `/api/memory/release`, or restart the app |
| App down after a settings change | Restart in progress or bad setting | Wait 1–2 min; check platform logs; revert the setting |

**Turn fault injection off** (this restarts the app):

```bash
az webapp config appsettings set -g rg-testapp-node -n testapp-node-2rqjmu --settings CHAOS_ENABLED=false
```

**Restart the app:**

```bash
az webapp restart -g rg-testapp-node -n testapp-node-2rqjmu
```

**Roll back a bad deployment:** revert the offending commit on `master` and push. The workflow
redeploys automatically. There is no staging slot to swap back to.

## 5. Escalation

There is a single owner: Alban Fetahi (`afetahi`). Changes beyond the actions above, such as scaling
up the plan or changing the infrastructure in `infra/main.bicep`, need the owner's approval.
