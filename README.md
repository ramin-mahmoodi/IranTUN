# IranTUN

An ultra-high-speed, serverless, and CPU-efficient WebSocket VLESS proxy tunnel designed for shared cPanel hosts. It completely bypasses host resource suspensions by utilizing fully asynchronous event-driven Node.js bridging, and includes a premium, modern camouflage portfolio site to completely deceive network and host scans.

## 🚀 Key Features

* **Serverless Architecture**: Bypasses the need for an intermediate domestic server. Your clients connect directly to the Iran cPanel host, which secure-bridges to the Foreign VPS exit node.
* **100% Camouflage Landing Page**: Serves a highly aesthetic tech startup portfolio at `https://YOUR_DOMAIN.com/` to pass hosting manual reviews.
* **Smart Analytics API Camouflage**: Intercepts VLESS connections at `/api/v1/analytics`. Standard GET web scans to this endpoint return a normal-looking JSON analytic metric dump, making it look 100% legitimate.
* **Anti-DPI Secure WebSocket (WSS)**: Supports wrapping VLESS-WS traffic in TLS using automatically generated self-signed SSL certificates on the VPS exit node. This encrypts headers at the transport layer, bypassing international gateway DPI throttling.
* **Dynamic Web Admin Control Panel**: Provides a live diagnostics dashboard with a hidden admin panel (accessible via `https://YOUR_DOMAIN.com/?secret=YOUR_UUID`). Includes real-time audit logs, active connections counter, and an interactive form to dynamically update and apply target VPS settings (IP, Port, Protocol, Path) instantly without server restarts.
* **Suspension-Proof Engine**: Avoids infinite loops or shell execution timeouts, maintaining **0.00% idle CPU** on the shared host, keeping it fully compliant with CloudLinux LVE limits.
* **Ultra-Low Latency**: High-speed, persistent full-duplex WebSocket pipe for maximum gaming and downstream throughput.

---

## 🛠️ Interactive One-Click Installation

To deploy the entire system (both the Foreign VPS exit node and your Iran cPanel Host), simply run the interactive Bash installer directly on your **Foreign VPS** as `root`:

```bash
git clone https://github.com/ramin-mahmoodi/IranTUN.git
cd IranTUN
sudo bash deploy.sh
```

This script will:
1. Prompt you to choose the bridge connection protocol:
   - **Plain WebSocket (ws)**: Runs on port `8080` (Fast but vulnerable to DPI throttling).
   - **Secure WebSocket (wss)**: Runs on port `8443` (Encrypted using a dynamically generated self-signed TLS certificate to bypass DPI).
2. Ask for your cPanel FTP credentials and target directory to upload all the bridge application and camouflage files automatically.
3. Generate a brand new secure random VLESS UUID dynamically.
4. Print ready-to-import client VLESS links in your terminal along with simple manual setup steps to activate the Node.js application in your cPanel dashboard.
