# GitHub Actions test app (Node.js)

A simple Node.js app to test and try App Service's integration with GitHub Actions.

## SRE Agent lab scenarios

This fork is also used as the workload for the Azure SRE Agent Level 200 labs. It adds
structured request logging, opt-in fault-injection endpoints, and a traffic generator,
so the agent has real failures to investigate. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/RUNBOOK.md](docs/RUNBOOK.md), and the infrastructure in [infra/main.bicep](infra/main.bicep).

### Fault-injection endpoints

The endpoints return `404` unless the app setting `CHAOS_ENABLED=true` is set. Every fault is capped.

| Endpoint | Effect | Limits |
|---|---|---|
| `GET /api/chaos` | Shows whether faults are enabled, plus current CPU and memory load | Always available |
| `GET /api/slow?ms=3000` | Delays the response | Max 10 s |
| `GET /api/error` | Throws an error: HTTP 500 plus a stack trace in the logs | — |
| `GET /api/cpu?seconds=10` | Busy-loops in the background | Max 30 s, at most 2 at once |
| `GET /api/memory?mb=50` | Holds memory until released | Max 200 MB in total |
| `GET /api/memory/release` | Frees the held memory | — |

To turn faults on or off (no deployment slot, so this targets production):

```bash
az webapp config appsettings set -g rg-testapp-node -n testapp-node-2rqjmu --settings CHAOS_ENABLED=true
az webapp config appsettings set -g rg-testapp-node -n testapp-node-2rqjmu --settings CHAOS_ENABLED=false
```

Changing an app setting restarts the app, which also releases any held memory.

### Generating traffic

```bash
bash scripts/traffic.sh https://testapp-node-2rqjmu.azurewebsites.net [normal|errors|slow|cpu|memory|mixed] [duration-seconds]
```

### Logs

Each request is logged to stdout as one JSON line, with `method`, `path`, `status`, `durationMs`
and `requestId`. Unhandled errors are logged with their stack trace and the same `requestId`. The
`x-request-id` response header lets you match a client response to its log lines.
