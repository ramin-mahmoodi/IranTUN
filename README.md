# Duud Tunnel

An ultra-high-speed, serverless, and CPU-efficient WebSocket VLESS proxy tunnel designed for shared cPanel hosts. It completely bypasses host resource suspensions by utilizing fully asynchronous event-driven Node.js bridging, and includes a premium, modern camouflage portfolio site to completely deceive network and host scans.

## 🚀 Key Features

* **Serverless Architecture**: Bypasses the need for an intermediate domestic server. Your clients connect directly to the Iran cPanel host, which secure-bridges to the Foreign VPS exit node.
* **100% Camouflage Landing Page**: Serves a highly aesthetic tech startup portfolio at `https://duud.lol/` to pass hosting manual reviews.
* **Smart Analytics API Camouflage**: Intercepts VLESS connections at `/api/v1/analytics`. Standard GET web scans to this endpoint return a normal-looking JSON analytic metric dump, making it look 100% legitimate.
* **Suspension-Proof Engine**: Avoids infinite loops or shell execution timeouts, maintaining **0.00% idle CPU** on the shared host, keeping it fully compliant with CloudLinux LVE limits.
* **Ultra-Low Latency**: High-speed, persistent full-duplex WebSocket pipe for maximum gaming and downstream throughput.

---

## 🛠️ Interactive One-Click Installation

To deploy the entire system (both the Foreign VPS and your Iran cPanel Host), just run the interactive Python deployer:

```bash
python deploy.py
```

This script will:
1. SSH into your Foreign VPS and set up Xray VLESS-WS on port 8080 automatically.
2. Log into your cPanel host via FTP and upload the bridge application and camouflage files to your targeted host path.
3. Print ready-to-import client VLESS links in your terminal.
