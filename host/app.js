const http = require('http');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

// Load configurations
const configPath = path.join(__dirname, 'config.json');
let config = {
  vpsIp: "YOUR_VPS_IP",
  vpsPort: 8080,
  vpsProtocol: "ws",
  vpsPath: "/metrics",
  tunnelPath: "/api/v1/analytics",
  secretUuid: "YOUR_UUID_HERE",
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

// In-Memory Status & Logs Tracking
const maxLogs = 100;
const bridgeLogs = [];
let activeConnections = 0;
let totalConnections = 0;
let totalBytesTransferred = 0;

function logEvent(type, message) {
  const timestamp = new Date().toISOString().replace('T', ' ').substring(0, 19);
  bridgeLogs.push({ timestamp, type, message });
  if (bridgeLogs.length > maxLogs) {
    bridgeLogs.shift();
  }
  console.log(`[${type}] ${timestamp} - ${message}`);
}

// Log initial server boot
logEvent("SYSTEM", "IranTUN Bridge Server initialized successfully.");

// Create HTTP Server
const server = http.createServer((req, res) => {
  const urlParts = req.url.split('?');
  const url = urlParts[0];
  const query = urlParts[1] || '';

  // 1. Camouflage GET Endpoint
  if (url === config.tunnelPath) {
    const params = new URLSearchParams(query);
    const secret = params.get('secret');

    // Secure Admin Diagnostic console access
    if (secret === config.secretUuid) {
      if (req.method === 'POST') {
        let body = '';
        req.on('data', chunk => {
          body += chunk.toString();
        });
        req.on('end', () => {
          try {
            const newConfig = JSON.parse(body);
            if (!newConfig.vpsIp || !newConfig.vpsPort) {
              res.writeHead(400, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
              return res.end(JSON.stringify({ error: "Missing VPS IP or Port" }));
            }
            config.vpsIp = newConfig.vpsIp;
            config.vpsPort = parseInt(newConfig.vpsPort);
            config.vpsProtocol = newConfig.vpsProtocol || 'ws';
            config.vpsPath = newConfig.vpsPath || '/metrics';
            
            fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
            logEvent("SYSTEM", `Configuration updated via Web Console. New target: ${config.vpsProtocol}://${config.vpsIp}:${config.vpsPort}${config.vpsPath}`);
            
            res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
            return res.end(JSON.stringify({ success: true }));
          } catch (err) {
            logEvent("ERROR", `Failed to save configuration: ${err.message}`);
            res.writeHead(500, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
            return res.end(JSON.stringify({ error: err.message }));
          }
        });
        return;
      }

      res.writeHead(200, { 
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      });
      const realStats = {
        real: true,
        status: "active",
        vpsIp: config.vpsIp,
        vpsPort: config.vpsPort,
        vpsProtocol: config.vpsProtocol || "ws",
        vpsPath: config.vpsPath || "/metrics",
        activeConnections,
        totalConnections,
        totalBytesTransferred,
        uptime: Math.floor(process.uptime()),
        memoryUsage: Math.floor(process.memoryUsage().heapUsed / 1024 / 1024) + " MB",
        logs: bridgeLogs
      };
      return res.end(JSON.stringify(realStats));
    }

    // Default camouflage json output
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
const wss = new WebSocket.Server({ 
  noServer: true,
  perMessageDeflate: false
});

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
  activeConnections++;
  totalConnections++;
  const clientIp = req.socket.remoteAddress || 'unknown';
  logEvent("INFO", `New tunnel connection requested from client: ${clientIp}`);

  // Construct target VPS URL
  const protocol = config.vpsProtocol || 'ws';
  const targetUrl = `${protocol}://${config.vpsIp}:${config.vpsPort}${config.vpsPath}`;
  const wsOptions = {
    perMessageDeflate: false
  };
  if (protocol === 'wss') {
    wsOptions.rejectUnauthorized = false; // Allow self-signed certificates
  }
  const remoteWs = new WebSocket(targetUrl, wsOptions);
  
  const bufferQueue = [];
  let isRemoteOpen = false;

  let idleTimeout;
  const refreshTimeout = () => {
    clearTimeout(idleTimeout);
    idleTimeout = setTimeout(() => {
      logEvent("WARN", `Session idle timeout triggered. Closing inactive tunnel.`);
      localWs.close();
      remoteWs.close();
    }, 180000); // 3 minutes idle timeout
  };

  refreshTimeout();

  // Pipe Local -> Remote
  localWs.on('message', (message, isBinary) => {
    refreshTimeout();
    const bytes = message.length || message.byteLength || 0;
    totalBytesTransferred += bytes;
    
    if (isRemoteOpen && remoteWs.readyState === WebSocket.OPEN) {
      remoteWs.send(message, { binary: isBinary });
    } else {
      bufferQueue.push({ message, isBinary });
    }
  });

  // Pipe Remote -> Local
  remoteWs.on('message', (message, isBinary) => {
    refreshTimeout();
    const bytes = message.length || message.byteLength || 0;
    totalBytesTransferred += bytes;
    if (localWs.readyState === WebSocket.OPEN) {
      localWs.send(message, { binary: isBinary });
    }
  });

  // Handle local closures/errors
  localWs.on('close', () => {
    activeConnections = Math.max(0, activeConnections - 1);
    logEvent("INFO", `Tunnel client connection closed.`);
    clearTimeout(idleTimeout);
    remoteWs.close();
  });
  localWs.on('error', (err) => {
    activeConnections = Math.max(0, activeConnections - 1);
    logEvent("ERROR", `Local tunnel error: ${err.message}`);
    localWs.close();
    remoteWs.close();
  });

  // Handle remote closures/errors
  remoteWs.on('open', () => {
    logEvent("SUCCESS", `Bridging completed. Connected to remote exit VPS node: ${config.vpsIp}`);
    isRemoteOpen = true;
    // Flush buffered client handshakes
    while (bufferQueue.length > 0) {
      const item = bufferQueue.shift();
      if (remoteWs.readyState === WebSocket.OPEN) {
        remoteWs.send(item.message, { binary: item.isBinary });
      }
    }
  });
  remoteWs.on('close', () => {
    logEvent("INFO", `Remote exit VPS closed connection.`);
    clearTimeout(idleTimeout);
    localWs.close();
  });
  remoteWs.on('error', (err) => {
    logEvent("ERROR", `Remote exit VPS connection error: ${err.message}`);
    localWs.close();
    remoteWs.close();
  });
});

// Start listening
const PORT = process.env.PORT || config.port || 3000;
server.listen(PORT, () => {
  logEvent("SYSTEM", `IranTUN Bridge listening on port ${PORT}`);
});
