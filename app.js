const express = require('express');
const os = require('os');

const app = express();
const port = process.env.PORT || 3000;
const startedAt = Date.now();


let visits = 0;

// A few fun facts served at random so the page feels alive.
const funFacts = [
  'Azure App Service runs over 40% of the web\'s WordPress sites.',
  'A deployment slot lets you swap staging into production with zero downtime.',
  'App Service can scale out automatically based on CPU, memory, or a schedule.',
  'The Free (F1) tier runs on shared workers, so it needs no dedicated VM quota.',
  'Managed identity lets your app reach a database with no passwords at all.'
];

function serverInfo() {
  const uptimeSeconds = Math.floor((Date.now() - startedAt) / 1000);
  return {
    greeting,
    message: `Hello World! Im a Web App living in Azure App Service,
    time: new Date().toISOString(),
    uptimeSeconds,
    visits,
    node: process.version,
    platform: `${process.platform}/${process.arch}`,
    hostname: os.hostname(),
    azure: {
      siteName: process.env.WEBSITE_SITE_NAME || '(running locally)',
      instanceId: (process.env.WEBSITE_INSTANCE_ID || 'local').slice(0, 8),
      region: process.env.REGION_NAME || 'local',
      sku: process.env.WEBSITE_SKU || 'n/a'
    }
  };
}

function formatUptime(seconds) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return `${h}h ${m}m ${s}s`;
}

// JSON APIs
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000), time: new Date().toISOString() });
});

app.get('/api/info', (req, res) => {
  res.json(serverInfo());
});

// Landing page
app.get('/', (req, res) => {
  visits++;
  const info = serverInfo();
  const fact = funFacts[Math.floor(Math.random() * funFacts.length)];

  res.type('html').send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${info.azure.siteName} - App Service</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
      font-family: 'Segoe UI', system-ui, -apple-system, sans-serif; color: #f5f7fa;
      background: linear-gradient(135deg, #0067c0 0%, #00337a 60%, #001b44 100%);
    }
    .card {
      width: min(680px, 92vw); background: rgba(255,255,255,0.08); backdrop-filter: blur(10px);
      border: 1px solid rgba(255,255,255,0.18); border-radius: 18px; padding: 36px 40px;
      box-shadow: 0 20px 50px rgba(0,0,0,0.35);
    }
    h1 { margin: 0 0 4px; font-size: 1.9rem; }
    .sub { opacity: 0.8; margin-bottom: 24px; }
    .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 14px; }
    .tile { background: rgba(0,0,0,0.20); border-radius: 12px; padding: 14px 16px; }
    .tile .label { font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.06em; opacity: 0.7; }
    .tile .value { font-size: 1.05rem; font-weight: 600; margin-top: 3px; word-break: break-word; }
    .fact { margin-top: 22px; font-style: italic; opacity: 0.9; border-left: 3px solid #5bc0ff; padding-left: 12px; }
    .foot { margin-top: 22px; font-size: 0.8rem; opacity: 0.65; }
    a { color: #9ad4ff; }
    .pulse { display:inline-block; width:9px; height:9px; border-radius:50%; background:#39d353; margin-right:6px; animation: p 1.6s infinite; }
    @keyframes p { 0%,100%{opacity:1} 50%{opacity:.3} }
  </style>
</head>
<body>
  <div class="card">
    <h1>👋 ${info.message}</h1>
    <div class="sub"><span class="pulse"></span>Live on Azure App Service</div>
    <div class="grid">
      <div class="tile"><div class="label">Site name</div><div class="value">${info.azure.siteName}</div></div>
      <div class="tile"><div class="label">Region</div><div class="value">${info.azure.region}</div></div>
      <div class="tile"><div class="label">Instance</div><div class="value">${info.azure.instanceId}</div></div>
      <div class="tile"><div class="label">Node.js</div><div class="value">${info.node}</div></div>
      <div class="tile"><div class="label">Server time</div><div class="value" id="time">${info.time}</div></div>
      <div class="tile"><div class="label">Uptime</div><div class="value" id="uptime">${formatUptime(info.uptimeSeconds)}</div></div>
      <div class="tile"><div class="label">Visits (this instance)</div><div class="value" id="visits">${info.visits}</div></div>
      <div class="tile"><div class="label">Platform</div><div class="value">${info.platform}</div></div>
    </div>
    <div class="fact">💡 ${fact}</div>
    <div class="foot">APIs: <a href="/api/info">/api/info</a> &middot; <a href="/api/health">/api/health</a></div>
  </div>
  <script>
    function fmt(s){var h=Math.floor(s/3600),m=Math.floor((s%3600)/60);return h+'h '+m+'m '+(s%60)+'s';}
    setInterval(async () => {
      try {
        const r = await fetch('/api/info');
        const d = await r.json();
        document.getElementById('time').textContent = d.time;
        document.getElementById('uptime').textContent = fmt(d.uptimeSeconds);
        document.getElementById('visits').textContent = d.visits;
      } catch (e) { /* ignore transient errors */ }
    }, 2000);
  </script>
</body>
</html>`);
});

app.listen(port, () => {
  console.log(`App listening on port ${port} (site: ${process.env.WEBSITE_SITE_NAME || 'local'})`);
});
