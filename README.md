# IranTUN

An ultra-high-speed, serverless, and CPU-efficient WebSocket VLESS proxy tunnel designed for shared cPanel hosts. It completely bypasses host resource suspensions by utilizing fully asynchronous event-driven Node.js bridging, and includes a premium, modern camouflage portfolio site to completely deceive network and host scans.

## 🚀 Key Features

* **Serverless Architecture**: Bypasses the need for an intermediate domestic server. Your clients connect directly to the Iran cPanel host, which secure-bridges to the Foreign VPS exit node.
* **100% Camouflage Landing Page**: Serves a highly aesthetic tech startup portfolio at `https://YOUR_DOMAIN.com/` to pass hosting manual reviews.
* **Smart Analytics API Camouflage**: Intercepts VLESS connections at `/api/v1/analytics`. Standard GET web scans to this endpoint return a normal-looking JSON analytic metric dump, making it look 100% legitimate.
* **Suspension-Proof Engine**: Avoids infinite loops or shell execution timeouts, maintaining **0.00% idle CPU** on the shared host, keeping it fully compliant with CloudLinux LVE limits.
* **Ultra-Low Latency**: High-speed, persistent full-duplex WebSocket pipe for maximum gaming and downstream throughput.

---

## 🛠️ Interactive One-Click Installation

You can deploy the entire setup using either the **Bash script** (recommended for Linux/macOS/Git-Bash) or the **Python script** (recommended for Windows).

### Option A: Via Bash Script (No dependencies required)
Simply run:

```bash
git clone https://github.com/ramin-mahmoodi/IranTUN.git
cd IranTUN
bash deploy.sh
```

### Option B: Via Python Script
First, install the required Python dependencies:

```bash
git clone https://github.com/ramin-mahmoodi/IranTUN.git
cd IranTUN
pip install -r requirements.txt
```

Then, run the interactive Python deployer:

```bash
python deploy.py
```

This script will:
1. SSH into your Foreign VPS and set up Xray VLESS-WS on port 8080 automatically.
2. Ask if you want to deploy to cPanel via **Fully Automated SSH** (Method 1: registers Node.js app automatically on CloudLinux selector!) or **Semi-Automated FTP** (Method 2: uploads files and gives direct cPanel GUI setup steps).
3. Generate a brand new secure random VLESS UUID dynamically.
4. Upload all the bridge application and camouflage files to your targeted host path.
5. Print ready-to-import client VLESS links in your terminal.
