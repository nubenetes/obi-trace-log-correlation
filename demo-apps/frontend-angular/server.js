/**
 * Angular SPA & SSR Demo Server
 * Demonstrates:
 * 1. Angular Server-Side Rendering (SSR) log interception by OBI eBPF (Node.js engine).
 * 2. Client-side browser telemetry forwarding (POST /api/telemetry/logs) with W3C traceparent.
 * 3. Working synchronous stdout logging vs decoupled background logging.
 */

const http = require('http');
const url = require('url');

const PORT = process.env.PORT || 8086;
const ASYNC_LOGGER = process.env.ASYNC_BACKGROUND_LOGGER === 'true';

// Helper for structured JSON logging directly to stdout (fd 1)
function logJSON(level, msg, extra = {}) {
  const payload = {
    timestamp: new Date().toISOString(),
    level,
    msg,
    pid: process.pid,
    runtime: 'angular-ssr-node20',
    ...extra
  };

  const line = JSON.stringify(payload) + '\n';

  if (ASYNC_LOGGER) {
    // BROKEN PATTERN: Decoupled asynchronous background logging
    // Dispatches log write to a future event loop tick, outside the HTTP request socket context.
    setTimeout(() => {
      process.stdout.write(line);
    }, 50);
  } else {
    // WORKING PATTERN: Synchronous write to stdout fd 1 within active request thread/event-loop context
    process.stdout.write(line);
  }
}

// In-memory HTML template representing pre-rendered Angular SSR output
function renderAngularSSRComponent(pageTitle, clientTraceId) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>${pageTitle}</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { font-family: system-ui, sans-serif; margin: 2rem; background: #0f172a; color: #f8fafc; }
    .card { background: #1e293b; padding: 1.5rem; border-radius: 8px; border: 1px solid #334155; }
    button { background: #3b82f6; color: white; border: none; padding: 0.5rem 1rem; border-radius: 4px; cursor: pointer; }
    pre { background: #020617; padding: 1rem; border-radius: 4px; overflow-x: auto; color: #38bdf8; }
  </style>
</head>
<body>
  <app-root>
    <div class="card">
      <h1>Angular 17+ SSR & SPA Demo</h1>
      <p>Server-side pre-rendered component at: <strong>${new Date().toISOString()}</strong></p>
      <p>Server PID: <code>${process.pid}</code> | SSR Mode: <code>${ASYNC_LOGGER ? 'Broken (Async Logger)' : 'Working (Sync Stdout)'}</code></p>
      <hr style="border-color: #334155; margin: 1rem 0;" />
      <h3>Client-Side W3C Traceparent Header Injection</h3>
      <p>Click below to simulate client-side HTTP call with W3C <code>traceparent</code>:</p>
      <button onclick="triggerClientCheckout()">Submit Order (Simulate SPA Call)</button>
      <pre id="output">Waiting for user interaction...</pre>
    </div>
  </app-root>

  <script>
    // Browser-side OpenTelemetry W3C traceparent generator simulation
    function generateTraceparent() {
      const traceId = Array.from(crypto.getRandomValues(new Uint8Array(16)))
        .map(b => b.toString(16).padStart(2, '0')).join('');
      const spanId = Array.from(crypto.getRandomValues(new Uint8Array(8)))
        .map(b => b.toString(16).padStart(2, '0')).join('');
      return { traceparent: '00-' + traceId + '-' + spanId + '-01', traceId, spanId };
    }

    async function triggerClientCheckout() {
      const trace = generateTraceparent();
      document.getElementById('output').textContent = 'Generated W3C traceparent: ' + trace.traceparent + '\\nSending to backend...';

      // 1. Send client telemetry log to server
      await fetch('/api/telemetry/logs', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'traceparent': trace.traceparent
        },
        body: JSON.stringify({
          event: 'ui_button_clicked',
          component: 'CheckoutComponent',
          clientTimestamp: new Date().toISOString()
        })
      });

      // 2. Call backend order API with traceparent
      const res = await fetch('/api/orders', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'traceparent': trace.traceparent
        },
        body: JSON.stringify({ item: 'pro-license', quantity: 1 })
      });

      const data = await res.json();
      document.getElementById('output').textContent = 
        'Response received!\\n' +
        'Trace ID: ' + trace.traceId + '\\n' +
        'Status: ' + data.status + '\\n' +
        'Check docker logs to see OBI zero-code trace enrichment on server stdout!';
    }
  </script>
</body>
</html>`;
}

const server = http.createServer((req, res) => {
  const parsedUrl = url.parse(req.url, true);
  const traceparent = req.headers['traceparent'] || 'none';

  if (parsedUrl.pathname === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK\n');
    return;
  }

  // 1. Angular Server-Side Rendering (SSR) Route
  if (parsedUrl.pathname === '/' || parsedUrl.pathname === '/ssr') {
    // During SSR, server-side pre-rendering code executes console/stdout logging
    logJSON('INFO', 'Angular SSR: Pre-rendering route /', {
      route: '/',
      service: 'frontend-angular-ssr',
      incoming_traceparent: traceparent,
      is_ssr: true
    });

    const html = renderAngularSSRComponent('Angular 17+ OBI SSR Demo', traceparent);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
    return;
  }

  // 2. Client-Side Browser Telemetry Ingestion Endpoint
  if (parsedUrl.pathname === '/api/telemetry/logs' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      let clientData = {};
      try { clientData = JSON.parse(body); } catch (_) {}

      // Server stdout write: OBI intercepts socket ingress, captures incoming traceparent,
      // and enriches this server log with the frontend's trace ID!
      logJSON('INFO', 'Frontend client telemetry log ingested', {
        service: 'frontend-angular-telemetry-bridge',
        incoming_traceparent: traceparent,
        client_event: clientData.event || 'unknown',
        client_component: clientData.component || 'unknown'
      });

      res.writeHead(202, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ingested: true }) + '\n');
    });
    return;
  }

  // 3. Simulated Backend API Endpoint for Orders
  if (parsedUrl.pathname === '/api/orders' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      logJSON('INFO', 'Order service processing checkout', {
        service: 'order-api',
        incoming_traceparent: traceparent,
        action: 'charge_credit_card'
      });

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'completed', orderId: 'ord-8921' }) + '\n');
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }) + '\n');
});

server.listen(PORT, () => {
  logJSON('INFO', `Angular SPA/SSR demo server listening on port ${PORT}`, {
    async_logger: ASYNC_LOGGER,
    mode: ASYNC_LOGGER ? 'BROKEN (Decoupled Async Queue)' : 'WORKING (Synchronous Stdout)'
  });
});
