const http = require('http');

// Standard JSON logging using Node.js
function logJSON(level, msg, extra = {}) {
  const line = JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    msg,
    pid: process.pid,
    ...extra
  }) + '\n';
  // Synchronous write to stdout fd 1
  process.stdout.write(line);
}

const server = http.createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK\n');
    return;
  }

  if (req.url === '/process') {
    // OBI intercepts this stdout write and correlates it with the HTTP request trace!
    logJSON('INFO', 'handling node.js async transaction', {
      url: req.url,
      method: req.method,
      service: 'nodejs-gateway'
    });

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'success', platform: 'nodejs-v20' }) + '\n');
    return;
  }

  res.writeHead(404);
  res.end('Not found\n');
});

const PORT = process.env.PORT || 8083;
server.listen(PORT, () => {
  logJSON('INFO', `Node.js service listening on port ${PORT}`);
});
