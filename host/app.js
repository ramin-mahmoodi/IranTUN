const http = require('http');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

// Load configurations
const configPath = path.join(__dirname, 'config.json');
let config = {
  vpsIp: "104.105.26.61",
  vpsPort: 8080,
  vpsPath: "/metrics",
  tunnelPath: "/api/v1/analytics",
  secretUuid: "cc654e3d-71b5-4a6c-b3a2-a3962b8a07c1",
  port: 3000
};

if (fs.existsSync(configPath)) {
  try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    console.log("Loaded configurations successfully.");
  } catch (err) {
    console.error("Error reading config.json, using defaults:", err);
  }
}

// Create HTTP Server
const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];

  // 1. Camouflage GET Endpoint
  if (url === config.tunnelPath) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    const fakeMetrics = {
      status: "active",
      node: "ir-edge-tehran-01",
      system_uptime: Math.floor(process.uptime()) + "s",
      ssl_status: "verified",
      latency_ms: Math.floor(Math.random() * 5) + 2,
      active_connections: Math.floor(Math.random() * 10) + 120,
      memory_usage: Math.floor(process.memoryUsage().heapUsed / 1024 / 1024) + "MB",
      load_average: [0.12, 0.08, 0.05],
      timestamp: new Date().toISOString()
    };
    return res.end(JSON.stringify(fakeMetrics));
  }

  // 2. Serve static dummy tech page
  let filePath = path.join(__dirname, 'public', url === '/' ? 'index.html' : url);
  
  // Prevent directory traversal
  if (!filePath.startsWith(path.join(__dirname, 'public'))) {
    res.writeHead(403);
    return res.end("Forbidden");
  }

  const ext = path.extname(filePath);
  let contentType = 'text/html';
  if (ext === '.css') contentType = 'text/css';
  else if (ext === '.js') contentType = 'application/javascript';
  else if (ext === '.json') contentType = 'application/json';
  else if (ext === '.png') contentType = 'image/png';
  else if (ext === '.jpg') contentType = 'image/jpeg';

  fs.readFile(filePath, (err, content) => {
    if (err) {
      if (err.code === 'ENOENT') {
        res.writeHead(404, { 'Content-Type': 'text/html' });
        res.end("<h1>404 Not Found</h1>");
      } else {
        res.writeHead(500);
        res.end("Internal Server Error: " + err.code);
      }
    } else {
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content, 'utf-8');
    }
  });
});

// Setup WebSocket Server bound to the same HTTP Server
const wss = new WebSocket.Server({ noServer: true });

server.on('upgrade', (request, socket, head) => {
  const pathname = request.url.split('?')[0];

  // Intercept the tunnel path only
  if (pathname === config.tunnelPath) {
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request);
    });
  } else {
    socket.destroy();
  }
});

wss.on('connection', (localWs, req) => {
  console.log("New encrypted tunnel link established");

  // Construct target VPS URL
  const targetUrl = `ws://${config.vpsIp}:${config.vpsPort}${config.vpsPath}`;
  const remoteWs = new WebSocket(targetUrl);

  let idleTimeout;
  const refreshTimeout = () => {
    clearTimeout(idleTimeout);
    idleTimeout = setTimeout(() => {
      console.log("Idle timeout triggered, releasing resources.");
      localWs.close();
      remoteWs.close();
    }, 180000); // 3 minutes idle timeout
  };

  refreshTimeout();

  // Pipe Local -> Remote
  localWs.on('message', (message, isBinary) => {
    refreshTimeout();
    if (remoteWs.readyState === WebSocket.OPEN) {
      remoteWs.send(message, { binary: isBinary });
    }
  });

  // Pipe Remote -> Local
  remoteWs.on('message', (message, isBinary) => {
    refreshTimeout();
    if (localWs.readyState === WebSocket.OPEN) {
      localWs.send(message, { binary: isBinary });
    }
  });

  // Handle local closures/errors
  localWs.on('close', () => {
    clearTimeout(idleTimeout);
    remoteWs.close();
  });
  localWs.on('error', (err) => {
    console.error("Local socket error:", err.message);
    localWs.close();
    remoteWs.close();
  });

  // Handle remote closures/errors
  remoteWs.on('open', () => {
    console.log("Successfully bridged to remote exit node");
  });
  remoteWs.on('close', () => {
    clearTimeout(idleTimeout);
    localWs.close();
  });
  remoteWs.on('error', (err) => {
    console.error("Remote exit node error:", err.message);
    localWs.close();
    remoteWs.close();
  });
});

// Start listening
const PORT = process.env.PORT || config.port || 3000;
server.listen(PORT, () => {
  console.log(`Duud Tunnel server listening on port ${PORT}`);
});
